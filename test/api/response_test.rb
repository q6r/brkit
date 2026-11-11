# frozen_string_literal: true

require_relative "../test_helper"
require "brkit/api"

module Brkit
  module API
    class ResponseTest < Minitest::Test
      def test_json_response_follows_rack_3_conventions
        status, headers, body = Response.json({ "name" => "João", "n" => 1 })
        assert_equal 200, status
        assert_equal "application/json", headers["content-type"]
        assert_equal "no-store", headers["cache-control"]
        assert_equal body.join.bytesize.to_s, headers["content-length"]
        assert_equal headers.keys.map(&:downcase), headers.keys
        assert_equal({ "name" => "João", "n" => 1 }, JSON.parse(body.first))
        assert_equal Encoding::UTF_8, body.first.encoding
      end

      def test_json_response_with_status_and_extra_headers
        status, headers, = Response.json([1], status: 201, headers: { "location" => "/x" })
        assert_equal [201, "/x"], [status, headers["location"]]
      end

      def test_extra_headers_override_the_defaults
        _status, headers, = Response.json({}, headers: { "cache-control" => "max-age=5" })
        assert_equal "max-age=5", headers["cache-control"]
      end

      def test_problem_response
        problem = Problem.method_not_allowed("POST", %w[GET])
        status, headers, body = Response.problem(problem, request_id: "abc")
        assert_equal 405, status
        assert_equal "application/problem+json", headers["content-type"]
        assert_equal "GET", headers["allow"]
        document = JSON.parse(body.first)
        assert_equal [405, "abc"], [document["status"], document["request_id"]]
        assert_equal headers["content-length"], body.first.bytesize.to_s
      end

      def test_bare_responses_have_no_content_headers
        status, headers, body = Response.bare(204, "allow" => "GET")
        assert_equal [204, { "allow" => "GET" }, []], [status, headers, body]
        original = { "etag" => "x" }
        Response.bare(304, original)[1]["extra"] = "y"
        assert_equal({ "etag" => "x" }, original, "the given headers must not be mutated")
      end

      def test_without_body_keeps_the_headers
        response = Response.json({ "a" => 1 })
        status, headers, body = Response.without_body(response)
        assert_equal [200, response[1], []], [status, headers, body]
        assert_equal "7", headers["content-length"]
      end

      def test_content_length_counts_bytes_not_characters
        _status, headers, = Response.build(200, "text/plain", "ação", {})
        assert_equal "6", headers["content-length"]
      end
    end
  end
end
