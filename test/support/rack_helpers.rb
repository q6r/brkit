# frozen_string_literal: true

require "stringio"

require "brkit/api"

module Brkit
  # Hand-built Rack environments, a reply wrapper and a Rack::Lint-style response check. The rack gem is not a
  # dependency (and not available in every environment), so the protocol rules are asserted here directly.
  module RackHelpers
    # A response as tests see it.
    Reply = Struct.new(:status, :headers, :body) do
      # @return [Object] the parsed JSON body
      def json
        JSON.parse(body)
      end

      def header(name)
        headers[name.downcase]
      end

      def problem?
        header("content-type").to_s.start_with?("application/problem+json")
      end
    end

    # @return [Hash] a Rack environment
    def env_for(method, path, query: "", headers: {}, body: nil, ip: "203.0.113.7")
      env = {
        "REQUEST_METHOD" => method.to_s.upcase, "SCRIPT_NAME" => "", "PATH_INFO" => path, "QUERY_STRING" => query,
        "SERVER_NAME" => "example.test", "SERVER_PORT" => "80", "SERVER_PROTOCOL" => "HTTP/1.1",
        "REMOTE_ADDR" => ip, "rack.url_scheme" => "http", "rack.input" => StringIO.new(body.to_s.b),
        "rack.errors" => StringIO.new
      }
      env["CONTENT_LENGTH"] = body.bytesize.to_s unless body.nil?
      headers.each { |name, value| env[rack_key(name)] = value }
      env
    end

    def rack_key(name)
      key = name.to_s.upcase.tr("-", "_")
      %w[CONTENT_TYPE CONTENT_LENGTH].include?(key) ? key : "HTTP_#{key}"
    end

    # Sends a request to +app+, checks the Rack contract and returns a {Reply}.
    def request(app, method, path, **options)
      response = app.call(env_for(method, path, **options))
      assert_rack_response(response, head: method.to_s.upcase == "HEAD")
      status, headers, body = response
      chunks = body.map { |chunk| chunk }
      Reply.new(status, headers, chunks.join)
    end

    # Posts +payload+ (a Hash, or raw JSON text) as application/json.
    def post_json(app, path, payload, headers: {}, **options)
      body = payload.is_a?(String) ? payload : JSON.generate(payload)
      request(app, :post, path, body: body, headers: { "Content-Type" => "application/json" }.merge(headers), **options)
    end

    # The rules of Rack 3 (SPEC) that matter for a response triple.
    def assert_rack_response(response, head: false)
      assert_kind_of Array, response
      assert_equal 3, response.length, "a Rack response has three parts"
      status, headers, body = response
      assert_kind_of Integer, status
      assert_includes 100..599, status
      assert_kind_of Hash, headers
      assert_headers_valid(status, headers)
      assert_respond_to body, :each
      chunks = body.map { |chunk| chunk }
      chunks.each { |chunk| assert_kind_of String, chunk }
      return if head || !headers.key?("content-length")

      assert_equal headers["content-length"].to_i, chunks.sum(&:bytesize), "content-length must match the body"
    end

    def assert_headers_valid(status, headers)
      headers.each do |name, value|
        assert_kind_of String, name
        assert_equal name.downcase, name, "Rack 3 header names are lower case (#{name})"
        refute_equal "status", name
        assert_kind_of String, value, "header #{name}"
        refute_match(/[\r\n\0]/, value, "control characters in header #{name}")
      end
      bodiless = status < 200 || [204, 304].include?(status)
      if bodiless
        refute headers.key?("content-length"), "#{status} must not carry content-length"
        refute headers.key?("content-type"), "#{status} must not carry content-type"
      else
        assert headers.key?("content-type"), "a #{status} response needs a content-type"
      end
    end
  end
end

Minitest::Test.include(Brkit::RackHelpers)
