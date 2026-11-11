# frozen_string_literal: true

require "time"

require_relative "response"

module Brkit
  module API
    # Serves the files of one directory (the playground in +public/+) with defensive path handling.
    #
    # A request path maps to a file only when every segment passes {SAFE_SEGMENT} (letters, digits and
    # a few punctuation marks, never starting with a dot, so +..+ and hidden files cannot match), the
    # resolved real path lies inside the root (symbolic links cannot escape it) and the target is a
    # regular file of at most 5 MiB. Anything else behaves like a missing file. Directories are never
    # listed; +/+ and paths ending in +/+ serve that directory's +index.html+.
    #
    # Responses carry the right +content-type+, a validator pair (+etag+, +last-modified+) honoured through
    # +if-none-match+ and +if-modified-since+, a cache policy (HTML revalidates, assets are cached for an
    # hour), +nosniff+ and, for HTML, a strict Content-Security-Policy.
    class Static
      MAX_FILE_BYTES = 5 * 1024 * 1024
      INDEX = "index.html"
      SAFE_SEGMENT = /\A[A-Za-z0-9][A-Za-z0-9._~@+-]{0,99}\z/

      MIME_TYPES = {
        ".html" => "text/html; charset=utf-8", ".htm" => "text/html; charset=utf-8",
        ".css" => "text/css; charset=utf-8", ".js" => "text/javascript; charset=utf-8",
        ".mjs" => "text/javascript; charset=utf-8", ".json" => "application/json", ".map" => "application/json",
        ".webmanifest" => "application/manifest+json", ".txt" => "text/plain; charset=utf-8",
        ".svg" => "image/svg+xml", ".png" => "image/png", ".jpg" => "image/jpeg", ".jpeg" => "image/jpeg",
        ".gif" => "image/gif", ".webp" => "image/webp", ".ico" => "image/vnd.microsoft.icon",
        ".woff2" => "font/woff2", ".wasm" => "application/wasm"
      }.freeze
      DEFAULT_TYPE = "application/octet-stream"

      HTML_POLICY = "default-src 'self'; img-src 'self' data:; style-src 'self'; script-src 'self'; " \
                    "connect-src 'self'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'; " \
                    "form-action 'self'"
      SVG_POLICY = "default-src 'none'; style-src 'unsafe-inline'; sandbox"

      # @return [String, nil] the real path of the served directory; nil when it does not exist
      attr_reader :root

      # @param root [String] directory to serve; a missing directory serves nothing
      # @param max_bytes [Integer] largest file served
      def initialize(root:, max_bytes: MAX_FILE_BYTES)
        @max_bytes = max_bytes
        @root = begin
          File.realpath(root)
        rescue SystemCallError
          nil
        end
      end

      # @param request [Request] a GET or HEAD request
      # @return [Array, nil] a Rack response, or nil when no file matches
      def call(request)
        file = locate(request.path)
        file && respond(request, file)
      end

      # Maps a request path to a real file below the root.
      #
      # @param path [String] decoded request path starting with +/+
      # @return [String, nil] the real path, or nil
      def locate(path)
        return nil unless @root

        names = names_for(path)
        return nil unless names

        real = File.realpath(File.join(@root, *names))
        real if inside_root?(real) && File.file?(real)
      rescue SystemCallError
        nil
      end

      private

      # @return [Array<String>, nil] safe segments (with the index file appended for directories)
      def names_for(path)
        segments = path.split("/", -1).drop(1)
        directory = segments.last == ""
        names = directory ? segments[0...-1] : segments
        return nil unless names.all? { |name| name.match?(SAFE_SEGMENT) }

        directory ? names + [INDEX] : names
      end

      def inside_root?(real)
        real == @root || real.start_with?("#{@root}/")
      end

      def respond(request, file)
        stat = File.stat(file)
        return nil if stat.size > @max_bytes

        validators = { "etag" => etag(stat), "last-modified" => stat.mtime.utc.httpdate,
                       "cache-control" => cache_control(file) }
        return Response.bare(304, validators) if fresh?(request, validators["etag"], stat.mtime)

        body = File.open(file, "rb") { |io| io.read(@max_bytes + 1) }
        return nil if body.bytesize > @max_bytes

        response(request, file, body, validators)
      end

      def response(request, file, body, validators)
        type = MIME_TYPES.fetch(File.extname(file).downcase, DEFAULT_TYPE)
        headers = { "content-type" => type, "content-length" => body.bytesize.to_s,
                    "x-content-type-options" => "nosniff" }.merge(validators)
        headers["content-security-policy"] = HTML_POLICY if type.start_with?("text/html")
        headers["content-security-policy"] = SVG_POLICY if type == "image/svg+xml"
        [200, headers, request.http_method == "HEAD" ? [] : [body]]
      end

      def etag(stat)
        nanoseconds = (stat.mtime.to_i * 1_000_000_000) + stat.mtime.nsec
        %("#{stat.size.to_s(16)}-#{nanoseconds.to_s(16)}")
      end

      def cache_control(file)
        File.extname(file).downcase.start_with?(".htm") ? "no-cache" : "public, max-age=3600"
      end

      # RFC 9110 section 13.2: if-none-match wins; if-modified-since is only consulted without it.
      def fresh?(request, etag, mtime)
        candidates = request.header("if-none-match")
        return candidates.strip == "*" || candidates.split(",").any? { |tag| same_tag?(tag, etag) } if candidates

        since = http_date(request.header("if-modified-since"))
        !since.nil? && mtime.to_i <= since.to_i
      end

      # Weak comparison: the W/ prefix is ignored.
      def same_tag?(left, right)
        left.strip.delete_prefix("W/") == right.delete_prefix("W/")
      end

      def http_date(text)
        text && Time.httpdate(text)
      rescue ArgumentError
        nil
      end
    end
  end
end
