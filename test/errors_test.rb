# frozen_string_literal: true

require_relative "test_helper"

module Brkit
  class ErrorsTest < Minitest::Test
    def test_hierarchy
      assert_operator InvalidInputError, :<, Error
      assert_operator ParseError, :<, Error
      assert_operator Error, :<, StandardError
    end

    def test_invalid_input_error_wraps_a_message
      error = InvalidInputError.new("something is off")
      assert_equal "something is off", error.message
      assert_equal 1, error.issues.length
      assert_equal :invalid, error.issues.first.code
    end

    def test_invalid_input_error_keeps_issues_in_order
      issues = [Issue.new(code: :a, message: "first", field: "x"), Issue.new(code: :b, message: "second")]
      error = InvalidInputError.new(issues)
      assert_equal "first; second", error.message
      assert_equal issues, error.issues
      assert_predicate error.issues, :frozen?
    end

    def test_for_builds_a_single_issue
      error = InvalidInputError.for(:bad, "nope", field: "seed")
      assert_equal [:bad], error.issues.map(&:code)
      assert_equal ["seed"], error.issues.map(&:field)
    end

    def test_parse_error_carries_a_position
      error = ParseError.new("broken", position: 12)
      assert_equal "broken", error.message
      assert_equal 12, error.position
      assert_nil ParseError.new("no position").position
    end
  end
end
