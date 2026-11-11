# frozen_string_literal: true

require_relative "../test_helper"
require "brkit/api"

module Brkit
  module API
    class ProblemTest < Minitest::Test
      def test_every_catalog_entry_has_a_status_and_title
        Problem::CATALOG.each do |slug, (status, title)|
          problem = Problem.new(slug)
          assert_equal [status, title, slug], [problem.status, problem.title, problem.slug]
          assert_includes 400..599, status
          assert_equal title, problem.message
        end
      end

      def test_catalog_statuses
        expected = { "bad-request" => 400, "invalid-parameter" => 400, "invalid-json" => 400, "not-found" => 404,
                     "method-not-allowed" => 405, "not-acceptable" => 406, "payload-too-large" => 413,
                     "uri-too-long" => 414, "unsupported-media-type" => 415, "validation-error" => 422,
                     "rate-limited" => 429, "internal-error" => 500 }
        assert_equal expected, Problem::CATALOG.transform_values(&:first)
      end

      def test_to_h_follows_rfc_9457
        problem = Problem.new("not-found", "no such thing")
        assert_equal({ type: "#{Problem::BASE_URI}not-found", title: "Not found", status: 404, detail: "no such thing" },
                     problem.to_h)
        with_id = problem.to_h(request_id: "req-1")
        assert_equal "req-1", with_id[:request_id]
        assert_match(%r{\Ahttps://github\.com/q6r/brkit/blob/main/docs/problems\.md#not-found\z}, with_id[:type])
      end

      def test_errors_are_serialised
        issues = [Issue.new(code: :missing, message: "cpf is required", field: "cpf")]
        hash = Problem.validation(issues).to_h
        assert_equal [{ code: "missing", message: "cpf is required", field: "cpf" }], hash[:errors]
        assert_equal "cpf is required", hash[:detail]
        assert_equal "2 fields are invalid", Problem.validation(issues * 2).detail
        assert_equal 400, Problem.invalid_parameter(issues).status
        assert_equal "2 parameters are invalid", Problem.invalid_parameter(issues * 2).detail
      end

      def test_factories
        too_large = Problem.payload_too_large(16)
        assert_equal [413, "the request body is larger than 16 bytes"], [too_large.status, too_large.detail]
        not_allowed = Problem.method_not_allowed("DELETE", %w[GET HEAD])
        assert_equal [405, "GET, HEAD"], [not_allowed.status, not_allowed.headers["allow"]]
        assert_includes not_allowed.detail, "DELETE"
        limited = Problem.rate_limited(7, "ratelimit-limit" => "40")
        assert_equal [429, "7", "40"], [limited.status, limited.headers["retry-after"], limited.headers["ratelimit-limit"]]
      end

      def test_problems_are_exceptions_of_the_library_hierarchy
        assert_operator Problem, :<, Brkit::Error
        assert_raises(Brkit::Error) { raise Problem.new("bad-request") }
      end

      def test_headers_and_errors_are_frozen
        problem = Problem.method_not_allowed("PUT", %w[GET])
        assert_predicate problem.headers, :frozen?
        assert_predicate Problem.validation([Issue.new(code: :a, message: "m")]).errors, :frozen?
      end
    end
  end
end
