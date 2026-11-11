# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../support/rack_helpers"

module Brkit
  module API
    class RequestTest < Minitest::Test
      def req(path = "/", **options)
        Request.new(env_for("GET", path, **options))
      end

      def assert_problem(status, slug = nil, message = nil, &)
        error = assert_raises(Problem, *message, &)
        assert_equal status, error.status
        assert_equal slug, error.slug if slug
        error
      end

      # -- method ------------------------------------------------------------------------------------------

      def test_http_method_is_upper_cased
        assert_equal "GET", Request.new(env_for("get", "/")).http_method
        assert_equal "POST", Request.new({ "REQUEST_METHOD" => "post" }).http_method
      end

      def test_malformed_methods_are_rejected
        ["", "G3T", "GET /x", "get\r\nx", nil, "A" * 11, "AB"].each do |verb|
          assert_problem(400, "bad-request") { Request.new({ "REQUEST_METHOD" => verb }).http_method }
        end
      end

      # -- path --------------------------------------------------------------------------------------------

      DECODED_PATHS = {
        "/" => "/", "" => "/", "/api/v1/cpf/validate" => "/api/v1/cpf/validate", "/a%20b" => "/a b",
        "/%C3%A9" => "/é", "/a%2Eb" => "/a.b", "/a%2eb" => "/a.b", "/%2e%2e/x" => "/../x", "/a/b/" => "/a/b/",
        "//" => "//", "/%7Euser" => "/~user", "/a+b" => "/a+b", "/%E2%82%AC" => "/€", "/..;/x" => "/..;/x"
      }.freeze

      def test_paths_are_decoded_segment_by_segment
        DECODED_PATHS.each do |raw, decoded|
          assert_equal decoded, req(raw).path, raw.inspect
          assert_equal Encoding::UTF_8, req(raw).path.encoding
        end
      end

      REJECTED_PATHS = [
        "/a%2Fb", "/a%2fb", "/%2F", "/a%5Cb", "/a%5cb", "/a%00b", "/%00", "/a%0Ab", "/a%0D%0Ab", "/a%7Fb", "/a%09b",
        "/%zz", "/%", "/a%2", "/%G0", "/%C3", "/%FF", "/%C0%AF", "/%ED%A0%80", "a/b", "*", "/a b", "/é", "/a\0b",
        "/a\nb", "/a\tb", "/a\u007Fb", "http://evil.test/x", "/a%252Fb%2"
      ].freeze

      def test_malformed_or_dangerous_paths_are_rejected
        REJECTED_PATHS.each do |raw|
          assert_problem(400, "bad-request") { req(raw).path }
        end
      end

      def test_percent_decoding_happens_once
        assert_equal "/a%2Fb", req("/a%252Fb").path
        assert_equal "/%2e%2e", req("/%252e%252e").path
      end

      def test_path_length_limit
        ok = "/#{'a' * 2047}"
        assert_equal 2048, ok.bytesize
        assert_equal ok, req(ok).path
        assert_problem(414, "uri-too-long") { req("#{ok}a").path }
      end

      # -- query -------------------------------------------------------------------------------------------

      QUERIES = {
        "" => {}, "a=1&b=2" => { "a" => "1", "b" => "2" }, "a" => { "a" => "" }, "a=" => { "a" => "" },
        "a=1&&b=2" => { "a" => "1", "b" => "2" }, "&" => {}, "a=%C3%A9" => { "a" => "é" }, "a=x+y" => { "a" => "x y" },
        "a=x%2By" => { "a" => "x+y" }, "a=%26&b=%3D" => { "a" => "&", "b" => "=" }, "k%20e=y" => { "k e" => "y" },
        "a=b=c" => { "a" => "b=c" }, "a=%E2%82%AC" => { "a" => "€" }, "cpf=529.982.247-25" => { "cpf" => "529.982.247-25" }
      }.freeze

      def test_query_parsing
        QUERIES.each do |raw, expected|
          assert_equal expected, req("/", query: raw).query, raw.inspect
        end
      end

      def test_query_is_frozen_and_memoised
        request = req("/", query: "a=1")
        assert_predicate request.query, :frozen?
        assert_same request.query, request.query
      end

      REJECTED_QUERIES = [
        "a=%zz", "a=%", "a=%FF", "a=%00", "a=%0A", "a=%0D%0Ax", "=x", "a=1&a=2", "a%20b=1&a+b=2", "a=é", "a=b c",
        "a=\0", "a=1\n", "%00=1", "a=%C3"
      ].freeze

      def test_malformed_queries_are_rejected
        REJECTED_QUERIES.each do |raw|
          assert_problem(400, "bad-request") { req("/", query: raw).query }
        end
      end

      def test_query_parameter_count_limit
        ok = (1..32).map { |index| "p#{index}=1" }.join("&")
        assert_equal 32, req("/", query: ok).query.length
        assert_problem(400, "bad-request") { req("/", query: "#{ok}&p33=1").query }
      end

      def test_query_length_limit
        ok = "a=#{'x' * 4094}"
        assert_equal 4096, ok.bytesize
        assert_equal 4094, req("/", query: ok).query["a"].length
        assert_problem(414, "uri-too-long") { req("/", query: "#{ok}x").query }
      end

      # -- headers -----------------------------------------------------------------------------------------

      def test_header_lookup_ignores_case
        request = req("/", headers: { "X-Request-Id" => "abc", "Accept" => "text/html", "Content-Type" => "x/y" })
        assert_equal "abc", request.header("x-request-id")
        assert_equal "abc", request.header("X-REQUEST-ID")
        assert_equal "text/html", request.header("accept")
        assert_equal "x/y", request.header("Content-Type")
        assert_nil request.header("origin")
      end

      def test_media_type_and_charset
        {
          "application/json" => ["application/json", nil],
          "Application/JSON; charset=UTF-8" => ["application/json", "utf-8"],
          "application/json;charset=\"utf-8\"" => ["application/json", "utf-8"],
          "text/plain; format=flowed; charset=iso-8859-1" => ["text/plain", "iso-8859-1"],
          " application/json " => ["application/json", nil]
        }.each do |header, (type, charset)|
          request = req("/", headers: { "Content-Type" => header })
          assert_equal type, request.media_type, header
          assert_value charset, request.charset, header
        end
        assert_nil req.media_type
        assert_nil req.charset
      end

      def test_content_length
        assert_equal 12, req("/", headers: { "Content-Length" => "12" }).content_length
        assert_equal 0, req("/", headers: { "Content-Length" => "0" }).content_length
        assert_nil req.content_length
        assert_nil req("/", headers: { "Content-Length" => "" }).content_length
        ["abc", "-1", "1.5", "1 2", "99999999999999", "0x10"].each do |value|
          assert_problem(400, "bad-request") { req("/", headers: { "Content-Length" => value }).content_length }
        end
      end

      ACCEPT = {
        nil => true, "" => true, "*/*" => true, "application/json" => true, "application/*" => true,
        "APPLICATION/JSON" => true, "text/html, application/json" => true, "text/html, */*;q=0.1" => true,
        "text/html;q=0.9, application/json;q=0.8" => true, "application/json;q=0.001" => true,
        "text/html" => false, "text/*" => false, "application/xml" => false, "image/png, text/plain" => false,
        "application/json;q=0" => false, "*/*;q=0" => false, "application/json;q=0, */*" => false,
        "application/*;q=0, application/json" => true, "*" => true, "garbage" => true, "text/html, garbage" => false
      }.freeze

      def test_accept_negotiation
        ACCEPT.each do |header, expected|
          headers = header.nil? ? {} : { "Accept" => header }
          assert_equal expected, req("/", headers: headers).accepts?("application/json"), header.inspect
        end
      end

      # -- body --------------------------------------------------------------------------------------------

      def test_body_reads_up_to_the_limit
        assert_equal "abc", Request.new(env_for("POST", "/", body: "abc")).body(3)
        assert_equal "", Request.new(env_for("POST", "/")).body(3)
        assert_equal "é", Request.new(env_for("POST", "/", body: "é")).body(2)
      end

      def test_body_over_the_limit_is_rejected
        assert_problem(413, "payload-too-large") { Request.new(env_for("POST", "/", body: "abcd")).body(3) }
      end

      def test_a_declared_oversize_body_is_rejected_without_reading
        env = env_for("POST", "/", body: "x" * 10)
        env["CONTENT_LENGTH"] = "10"
        assert_problem(413) { Request.new(env).body(3) }
        assert_equal 0, env["rack.input"].pos, "the body must not be read"
      end

      def test_a_chunked_body_without_content_length_is_still_bounded
        env = env_for("POST", "/", body: "x" * 1000)
        env.delete("CONTENT_LENGTH")
        assert_problem(413) { Request.new(env).body(100) }
        assert_operator env["rack.input"].pos, :<=, 101, "no more than limit + 1 bytes are read"
      end

      def test_the_default_limit_comes_from_the_environment
        env = env_for("POST", "/", body: "abcd")
        env[Request::BODY_LIMIT_KEY] = 3
        assert_problem(413) { Request.new(env).body }
        env = env_for("POST", "/", body: "abcd")
        env[Request::BODY_LIMIT_KEY] = 4
        assert_equal "abcd", Request.new(env).body
      end

      def test_a_body_that_is_not_utf8_is_rejected
        assert_problem(400, "bad-request") { Request.new(env_for("POST", "/", body: "ab\xFFcd".b)).body(100) }
      end

      def test_a_missing_input_stream_reads_as_empty
        env = env_for("POST", "/")
        env.delete("rack.input")
        assert_equal "", Request.new(env).body(10)
      end

      # -- json body ---------------------------------------------------------------------------------------

      def json_request(body, type: "application/json")
        Request.new(env_for("POST", "/", body: body, headers: { "Content-Type" => type }))
      end

      def test_json_body_returns_the_object
        assert_equal({ "a" => 1, "b" => [true, nil, "é"] }, json_request('{"a":1,"b":[true,null,"é"]}').json_body)
        assert_equal({}, json_request("{}").json_body)
        assert_equal({ "a" => 1 }, json_request('{"a":1}', type: "application/json; charset=UTF-8").json_body)
      end

      def test_json_body_requires_the_json_media_type
        ["text/plain", "application/x-www-form-urlencoded", "application/jsonp", "application/json+x", "", nil,
         "application/json; charset=iso-8859-1", "application/json; charset=utf-16"].each do |type|
          assert_problem(415, "unsupported-media-type") { json_request('{"a":1}', type: type).json_body }
        end
      end

      def test_json_body_rejects_empty_and_malformed_input
        ["", "   ", "\n"].each { |body| assert_problem(400, "invalid-json") { json_request(body).json_body } }
        ["{", "{'a':1}", "{\"a\":}", "nope", "{\"a\":NaN}", "{\"a\":Infinity}", "﻿{}", "{} x", "{\"a\":1,}"].each do |body|
          assert_problem(400, "invalid-json", body.inspect) { json_request(body).json_body }
        end
      end

      # The same body must mean the same thing under every json version: a repeated key is ambiguous, so it is refused.
      def test_json_body_rejects_a_repeated_key
        ['{"a":1,"a":2}', '{"x":{"a":1,"a":1}}', '[{"a":1,"a":2}]'].each do |body|
          assert_problem(400, "invalid-json", body) { json_request(body).json_body }
        end
      end

      def test_json_body_is_plain_hashes_and_arrays
        data = json_request('{"a":{"b":[{"c":1}]}}').json_body
        assert_instance_of Hash, data
        assert_instance_of Hash, data["a"]
        assert_instance_of Hash, data["a"]["b"].first
        data["a"]["b"].first["c"] = 2 # a plain Hash: overwriting a key is fine once parsing is over
        assert_equal 2, data["a"]["b"].first["c"]
      end

      def test_json_body_must_be_an_object
        ["[]", "[1]", "\"text\"", "1", "true", "null"].each do |body|
          error = assert_problem(400, "invalid-json", body) { json_request(body).json_body }
          assert_includes error.detail, "object"
        end
      end

      def test_json_nesting_is_limited
        deep = ->(levels) { "#{'{"a":' * levels}1#{'}' * levels}" }
        assert_kind_of Hash, json_request(deep.call(8)).json_body
        assert_problem(400, "invalid-json") { json_request(deep.call(9)).json_body }
        assert_problem(400, "invalid-json") { json_request("[" * 5000).json_body }
      end

      def test_json_never_creates_arbitrary_objects
        data = json_request('{"json_class":"Range","a":1}').json_body
        assert_kind_of Hash, data
        assert_equal "Range", data["json_class"]
      end

      def test_json_errors_do_not_echo_the_input
        error = assert_problem(400, "invalid-json") { json_request("{secret-token-1234").json_body }
        refute_includes error.detail, "secret-token"
      end

      # -- client address ------------------------------------------------------------------------------------

      def test_ip_uses_remote_addr_by_default
        assert_equal "203.0.113.7", req.ip
        assert_equal "203.0.113.7", req("/", headers: { "X-Forwarded-For" => "198.51.100.1" }).ip
        assert_equal "2001:db8::1", req("/", ip: "2001:db8::1").ip
      end

      def test_ip_can_trust_the_right_most_forwarded_address
        request = req("/", headers: { "X-Forwarded-For" => "10.9.9.9, 198.51.100.1, 203.0.113.99" })
        assert_equal "203.0.113.99", request.ip(trust_proxy: true)
        assert_equal "203.0.113.7", req.ip(trust_proxy: true)
        assert_equal "203.0.113.7", req("/", headers: { "X-Forwarded-For" => "evil\r\nvalue" }).ip(trust_proxy: true)
        assert_equal "203.0.113.7", req("/", headers: { "X-Forwarded-For" => "not an ip" }).ip(trust_proxy: true)
      end

      def test_ip_is_bounded_and_never_blank
        assert_equal "unknown", Request.new({}).ip
        assert_equal 45, Request.new({ "REMOTE_ADDR" => "a" * 100 }).ip.length
      end

      def test_request_id_comes_from_the_environment
        env = env_for("GET", "/")
        env[Request::REQUEST_ID_KEY] = "abc-123"
        assert_equal "abc-123", Request.new(env).request_id
        assert_nil req.request_id
      end

      def test_percent_decode_directly
        assert_equal "a b", Request.percent_decode("a%20b")
        assert_equal "a b", Request.percent_decode("a+b", plus: true)
        assert_equal "a+b", Request.percent_decode("a+b")
        assert_problem(400) { Request.percent_decode("%") }
      end
    end
  end
end
