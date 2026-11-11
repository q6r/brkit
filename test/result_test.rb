# frozen_string_literal: true

require_relative "test_helper"

module Brkit
  class ResultTest < Minitest::Test
    def build(**overrides)
      Result.new(**{ kind: :demo, input: +"abc", normalized: "ABC", formatted: "A-B-C",
                     errors: [], details: { list: [1, { deep: +"x" }] } }.merge(overrides))
    end

    def test_valid_when_there_are_no_errors
      assert_predicate build, :valid?
      refute_predicate build(errors: [Issue.new(code: :bad, message: "bad")]), :valid?
    end

    def test_exposes_the_documented_attributes
      result = build
      assert_equal "demo", result.kind
      assert_equal "abc", result.input
      assert_equal "ABC", result.normalized
      assert_equal "A-B-C", result.formatted
      assert_equal [], result.errors
      assert_equal({ list: [1, { deep: "x" }] }, result.details)
    end

    def test_defaults
      result = Result.new(kind: "x", input: "y")
      assert_nil result.normalized
      assert_nil result.formatted
      assert_empty result.errors
      assert_empty result.details
    end

    def test_is_deeply_frozen
      result = build
      assert_predicate result, :frozen?
      assert_predicate result.errors, :frozen?
      assert_predicate result.details, :frozen?
      assert_predicate result.details[:list], :frozen?
      assert_predicate result.details[:list].last, :frozen?
      assert_predicate result.details[:list].last[:deep], :frozen?
      assert_raises(FrozenError) { result.details[:new] = 1 }
    end

    def test_does_not_freeze_objects_owned_by_the_caller
      input = +"abc"
      errors = [Issue.new(code: :a, message: "m")]
      details = { note: +"n" }
      Result.new(kind: "x", input: input, errors: errors, details: details)
      refute_predicate input, :frozen?
      refute_predicate errors, :frozen?
      refute_predicate details, :frozen?
      refute_predicate details[:note], :frozen?
    end

    def test_error_messages
      issues = [Issue.new(code: :a, message: "first"), Issue.new(code: :b, message: "second", field: "key")]
      assert_equal %w[first second], build(errors: issues).error_messages
    end

    def test_to_h_is_json_friendly
      issue = Issue.new(code: :checksum, message: "bad digit", field: nil)
      hash = build(errors: [issue]).to_h
      assert_equal %i[kind input valid normalized formatted errors details], hash.keys
      assert_equal false, hash[:valid]
      assert_equal [{ code: "checksum", message: "bad digit" }], hash[:errors]
    end

    def test_json_round_trip
      result = build
      parsed = JSON.parse(JSON.generate(result))
      assert_equal "demo", parsed["kind"]
      assert_equal true, parsed["valid"]
      assert_equal [1, { "deep" => "x" }], parsed["details"]["list"]
      assert_equal JSON.parse(result.to_json), parsed
    end

    def test_pattern_matching_support
      case build
      in { kind: "demo", normalized: String => normalized }
        assert_equal "ABC", normalized
      else
        flunk "Result should support pattern matching"
      end
    end

    def test_value_equality
      assert_equal build, build
      refute_equal build, build(input: "other")
    end

    def test_issue_is_frozen_and_serialises_without_empty_field
      issue = Issue.new(code: :x, message: "m")
      assert_predicate issue, :frozen?
      assert_equal({ code: "x", message: "m" }, issue.to_h)
      assert_equal({ code: "x", message: "m", field: "name" }, Issue.new(code: :x, message: "m", field: "name").to_h)
    end
  end
end
