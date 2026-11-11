# frozen_string_literal: true

require "json"

require_relative "problem"

module Brkit
  module API
    # A read-only view of a Rack environment with strict, bounded parsing.
    #
    # Everything that comes from the client is checked here once: the path is percent-decoded segment by
    # segment (so +%2F+ can never forge a separator) and rejected when it holds control characters or NUL
    # bytes; the query string is decoded strictly (bad escapes are errors, not silently kept) and limited in
    # size and parameter count; the body is read through a hard size limit; JSON is parsed with limited
    # nesting and no object creation.
    class Request
      MAX_PATH_BYTES = 2_048
      MAX_QUERY_BYTES = 4_096
      MAX_QUERY_PARAMS = 32
      MAX_JSON_NESTING = 8
      DEFAULT_MAX_BODY_BYTES = 16_384
      # Rack env key under which {Middleware::BodyLimit} publishes the configured limit.
      BODY_LIMIT_KEY = "brkit.max_body_bytes"
      # Rack env key under which {Middleware::RequestId} publishes the request id.
      REQUEST_ID_KEY = "brkit.request_id"
      METHOD = /\A[A-Z]{3,10}\z/
      CONTROL = /[\x00-\x1F\x7F]/
      PERCENT_ENCODED = /\A(?:[^%]|%\h\h)*\z/

      # @return [Hash] the Rack environment
      attr_reader :env

      # @param env [Hash] a Rack environment
      def initialize(env)
        @env = env
      end

      # @return [String] upper-case HTTP method
      # @raise [Problem] 400 when it is not a plain token
      def http_method
        @http_method ||= begin
          verb = @env["REQUEST_METHOD"].to_s.upcase
          raise Problem.new("bad-request", "malformed request method") unless verb.match?(METHOD)

          verb
        end
      end

      # The decoded request path, always starting with a slash. Each segment is percent-decoded on its own and
      # may not contain +/+, +\+, NUL or other control characters afterwards. Dot segments are left alone:
      # the router matches exact paths and {Static} refuses them.
      #
      # @return [String]
      # @raise [Problem] 400 for malformed encodings or forbidden characters, 414 when too long
      def path
        @path ||= decode_path(@env["PATH_INFO"].to_s)
      end

      # @return [Hash{String=>String}] decoded query parameters (frozen)
      # @raise [Problem] 400 for malformed encodings, duplicates or too many parameters; 414 when too long
      def query
        @query ||= parse_query(@env["QUERY_STRING"].to_s)
      end

      # @param name [String] header name in any case, e.g. +"Content-Type"+
      # @return [String, nil]
      def header(name)
        key = name.to_s.upcase.tr("-", "_")
        key = "HTTP_#{key}" unless %w[CONTENT_TYPE CONTENT_LENGTH].include?(key)
        value = @env[key]
        value&.to_s
      end

      # @return [String, nil] the media type of the body, lower case and without parameters
      def media_type
        header("content-type")&.split(";")&.first&.strip&.downcase
      end

      # @return [String, nil] the +charset+ parameter of the content type, lower case
      def charset
        parameter = header("content-type").to_s.split(";").drop(1).map(&:strip).find do |part|
          part.downcase.start_with?("charset=")
        end
        parameter&.split("=", 2)&.last&.delete('"')&.downcase
      end

      # @return [Integer, nil] the declared body size
      # @raise [Problem] 400 when the header is not a plain number
      def content_length
        value = header("content-length")
        return nil if value.nil? || value.strip.empty?
        raise Problem.new("bad-request", "invalid Content-Length header") unless value.strip.match?(/\A\d{1,12}\z/)

        value.strip.to_i
      end

      # Whether the client accepts +wanted+, following RFC 9110 content negotiation: the most specific
      # matching range decides and +q=0+ means "not acceptable". A missing header, or one without any
      # well-formed range (such as the bare +*+ some HTTP libraries send), accepts everything.
      #
      # @param wanted [String] e.g. +"application/json"+
      def accepts?(wanted)
        ranges = header("accept").to_s.split(",").filter_map { |range| parse_range(range) }
        return true if ranges.empty?

        type, subtype = wanted.split("/")
        best = ranges.filter_map { |main, sub, quality| rank(main, sub, quality, type, subtype) }.max_by(&:first)
        !best.nil? && best.last.positive?
      end

      # Reads the body, never more than +limit+ bytes.
      #
      # @param limit [Integer]
      # @return [String] valid UTF-8
      # @raise [Problem] 413 when larger than +limit+, 400 when not valid UTF-8
      def body(limit = @env.fetch(BODY_LIMIT_KEY, DEFAULT_MAX_BODY_BYTES))
        declared = content_length
        raise Problem.payload_too_large(limit) if declared && declared > limit

        input = @env["rack.input"]
        data = input ? (input.read(limit + 1) || "") : ""
        raise Problem.payload_too_large(limit) if data.bytesize > limit

        text = data.dup.force_encoding(Encoding::UTF_8)
        raise Problem.new("bad-request", "the request body is not valid UTF-8") unless text.valid_encoding?

        text
      end

      # Parses the body as a JSON object.
      #
      # @return [Hash{String=>Object}]
      # @raise [Problem] 415 unless +application/json+ (UTF-8), 400 for empty or invalid JSON or a non-object
      def json_body
        unless media_type == "application/json" && (charset.nil? || charset == "utf-8")
          raise Problem.new("unsupported-media-type", "send the body as application/json (UTF-8)")
        end

        raw = body
        raise Problem.new("invalid-json", "the request body is empty") if raw.strip.empty?

        # JSON.parse never instantiates classes named in the document (create_additions is off by default;
        # json 3 no longer accepts the keyword at all), and the nesting depth is bounded.
        data = JSON.parse(raw, max_nesting: MAX_JSON_NESTING, allow_nan: false)
        raise Problem.new("invalid-json", "the body must be a JSON object") unless data.is_a?(Hash)

        data
      rescue JSON::ParserError
        raise Problem.new("invalid-json", "the body is not valid JSON (at most #{MAX_JSON_NESTING} levels of nesting)")
      end

      # @param trust_proxy [Boolean] use the right-most +X-Forwarded-For+ entry (the address the nearest proxy saw)
      # @return [String] the client address, used as the rate-limit key
      def ip(trust_proxy: false)
        remote = @env["REMOTE_ADDR"].to_s[0, 45]
        remote = "unknown" if remote.empty?
        return remote unless trust_proxy

        forwarded = header("x-forwarded-for").to_s.split(",").map(&:strip).reject(&:empty?).last
        forwarded&.match?(/\A[0-9A-Fa-f:.]{2,45}\z/) ? forwarded : remote
      end

      # @return [String, nil] the id assigned by {Middleware::RequestId}
      def request_id
        @env[REQUEST_ID_KEY]
      end

      class << self
        # Percent-decodes +text+ strictly.
        #
        # @param text [String] ASCII text where +%XX+ stands for one byte
        # @param plus [Boolean] treat +"+"+ as a space (form encoding)
        # @return [String] valid UTF-8 without control characters
        # @raise [Problem] 400 for a stray +%+, invalid UTF-8 or control characters
        def percent_decode(text, plus: false)
          raise Problem.new("bad-request", "malformed percent-encoding") unless text.match?(PERCENT_ENCODED)

          source = plus ? text.tr("+", " ") : text
          decoded = source.b.gsub(/%\h\h/n) { |escape| escape[1, 2].hex.chr }.force_encoding(Encoding::UTF_8)
          raise Problem.new("bad-request", "percent-encoded text is not valid UTF-8") unless decoded.valid_encoding?
          raise Problem.new("bad-request", "control characters are not allowed") if decoded.match?(CONTROL)

          decoded
        end

        # @param raw [String] a request target part that must hold visible ASCII only
        # @param what [String] for the error message
        # @return [String] the same bytes tagged as UTF-8 (they are ASCII, so always valid)
        def ascii(raw, what)
          text = raw.b
          raise Problem.new("bad-request", "#{what} must be percent-encoded ASCII") unless text.match?(/\A[!-~]*\z/n)

          text.force_encoding(Encoding::UTF_8)
        end
      end

      private

      def decode_path(raw)
        raw = "/" if raw.empty?
        raise Problem.new("uri-too-long", "the request path is longer than #{MAX_PATH_BYTES} bytes") if
          raw.bytesize > MAX_PATH_BYTES

        text = self.class.ascii(raw, "the request path")
        raise Problem.new("bad-request", "the request path must start with /") unless text.start_with?("/")

        text.split("/", -1).map { |segment| decode_segment(segment) }.join("/")
      end

      def decode_segment(segment)
        decoded = self.class.percent_decode(segment)
        raise Problem.new("bad-request", "encoded path separators are not allowed") if decoded.match?(%r{[/\\]})

        decoded
      end

      def parse_query(raw)
        return {}.freeze if raw.empty?
        raise Problem.new("uri-too-long", "the query string is longer than #{MAX_QUERY_BYTES} bytes") if
          raw.bytesize > MAX_QUERY_BYTES

        pairs = self.class.ascii(raw, "the query string").split("&").reject(&:empty?)
        raise Problem.new("bad-request", "more than #{MAX_QUERY_PARAMS} query parameters") if
          pairs.length > MAX_QUERY_PARAMS

        pairs.each_with_object({}) do |pair, params|
          name, value = pair.split("=", 2)
          key = self.class.percent_decode(name.to_s, plus: true)
          raise Problem.new("bad-request", "empty parameter name") if key.empty?
          raise Problem.new("bad-request", "parameter #{key[0, 40].inspect} is given more than once") if params.key?(key)

          params[key] = self.class.percent_decode(value.to_s, plus: true)
        end.freeze
      end

      # Parses one Accept range into [type, subtype, q]; nil when it is not shaped like +type/subtype+.
      def parse_range(range)
        media, *params = range.split(";").map(&:strip)
        main, sub = media.to_s.downcase.split("/")
        return nil if main.to_s.empty? || sub.to_s.empty?

        quality = params.filter_map { |param| param[/\Aq=([0-9.]+)\z/i, 1] }.first
        [main, sub, quality ? quality.to_f : 1.0]
      end

      # [specificity, q] when the range covers the wanted type, nil otherwise.
      def rank(main, sub, quality, type, subtype)
        return [3, quality] if main == type && sub == subtype
        return [2, quality] if main == type && sub == "*"

        [1, quality] if main == "*" && sub == "*"
      end
    end
  end
end
