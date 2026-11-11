# frozen_string_literal: true

require_relative "../test_helper"
require "brkit/api"

module Brkit
  module API
    class ParamsTest < Minitest::Test
      def specs
        [
          Params.string(:cpf, required: true, max_length: 20),
          Params.integer(:count, default: 1, min: 1, max: 100),
          Params.boolean(:formatted, default: false),
          Params.string(:uf, enum: %w[SP RJ], fold: :upcase, max_length: 2),
          Params.integer(:seed, min: 0, max: 4_294_967_295)
        ]
      end

      def problem_for(specs, raw, kind: :query)
        assert_raises(Problem) do
          kind == :query ? Params.from_query(specs, raw) : Params.from_body(specs, raw)
        end
      end

      def codes(error)
        error.errors.map { |issue| [issue.field, issue.code] }
      end

      # -- query -------------------------------------------------------------------------------------------

      def test_defaults_apply_when_a_parameter_is_absent
        assert_equal({ cpf: "1", count: 1, formatted: false }, Params.from_query(specs, { "cpf" => "1" }))
      end

      def test_values_are_converted
        values = Params.from_query(specs, { "cpf" => "x", "count" => "7", "formatted" => "true", "uf" => "rj",
                                            "seed" => "42" })
        assert_equal({ cpf: "x", count: 7, formatted: true, uf: "RJ", seed: 42 }, values)
      end

      def test_a_missing_required_parameter
        error = problem_for(specs, {})
        assert_equal 400, error.status
        assert_equal "invalid-parameter", error.slug
        assert_equal [["cpf", :missing]], codes(error)
        assert_equal "cpf is required", error.detail
      end

      def test_unknown_parameters_are_rejected_and_listed
        error = problem_for(specs, { "cpf" => "1", "nope" => "1", "extra" => "2" })
        assert_equal [["nope", :unknown_parameter], ["extra", :unknown_parameter]], codes(error)
        assert_includes error.errors.first.message, "allowed: cpf, count, formatted, uf, seed"
        assert_equal "2 parameters are invalid", error.detail
      end

      def test_unknown_parameter_names_are_truncated_in_messages
        error = problem_for(specs, { "cpf" => "1", ("x" * 500) => "1" })
        assert_operator error.errors.first.message.length, :<, 200
        assert_equal 40, error.errors.first.field.length
      end

      def test_only_ten_unknown_parameters_are_reported
        raw = { "cpf" => "1" }.merge((1..30).to_h { |index| ["p#{index}", "1"] })
        assert_equal 10, problem_for(specs, raw).errors.length
      end

      def test_integer_parsing
        { "1" => 1, "7" => 7, "100" => 100, "007" => 7 }.each do |text, value|
          assert_equal value, Params.from_query(specs, { "cpf" => "x", "count" => text })[:count], text
        end
        ["abc", "1.5", "1e2", "", " 1", "1 ", "+1", "0x10", "12345678901", "--1"].each do |text|
          assert_equal [["count", :invalid_integer]], codes(problem_for(specs, { "cpf" => "x", "count" => text })), text
        end
      end

      def test_integer_ranges
        ["0", "101", "-1", "999"].each do |text|
          assert_equal [["count", :out_of_range]], codes(problem_for(specs, { "cpf" => "x", "count" => text })), text
        end
        assert_equal 1, Params.from_query(specs, { "cpf" => "x", "count" => "1" })[:count]
        assert_equal 4_294_967_295, Params.from_query(specs, { "cpf" => "x", "seed" => "4294967295" })[:seed]
        assert_equal [["seed", :out_of_range]], codes(problem_for(specs, { "cpf" => "x", "seed" => "4294967296" }))
        assert_equal [["seed", :out_of_range]], codes(problem_for(specs, { "cpf" => "x", "seed" => "-1" }))
      end

      def test_boolean_parsing
        { "true" => true, "TRUE" => true, "True" => true, "1" => true, "false" => false, "FALSE" => false,
          "0" => false }.each do |text, value|
          assert_equal value, Params.from_query(specs, { "cpf" => "x", "formatted" => text })[:formatted], text
        end
        ["yes", "no", "", "2", "t", "on", "truee"].each do |text|
          assert_equal [["formatted", :invalid_boolean]],
                       codes(problem_for(specs, { "cpf" => "x", "formatted" => text })), text.inspect
        end
      end

      def test_enum_and_fold
        assert_equal "SP", Params.from_query(specs, { "cpf" => "x", "uf" => "sp" })[:uf]
        assert_equal "SP", Params.from_query(specs, { "cpf" => "x", "uf" => "Sp" })[:uf]
        error = problem_for(specs, { "cpf" => "x", "uf" => "MG" })
        assert_equal [["uf", :not_allowed]], codes(error)
        assert_includes error.errors.first.message, "SP, RJ"
      end

      def test_string_length_limit
        assert_equal "a" * 20, Params.from_query(specs, { "cpf" => "a" * 20 })[:cpf]
        assert_equal [["cpf", :too_long]], codes(problem_for(specs, { "cpf" => "a" * 21 }))
        assert_equal 256, Params::DEFAULT_MAX_LENGTH
        loose = [Params.string(:v)]
        assert_equal "a" * 256, Params.from_query(loose, { "v" => "a" * 256 })[:v]
        assert_equal [["v", :too_long]], codes(problem_for(loose, { "v" => "a" * 257 }))
      end

      def test_an_empty_string_is_a_value_not_an_absence
        assert_equal "", Params.from_query(specs, { "cpf" => "" })[:cpf]
      end

      def test_all_problems_are_collected
        error = problem_for(specs, { "count" => "x", "formatted" => "maybe", "uf" => "MG", "other" => "1" })
        assert_equal %w[other cpf count formatted uf], error.errors.map(&:field)
      end

      def test_optional_parameters_without_a_default_are_left_out
        assert_equal [:cpf, :count, :formatted], Params.from_query(specs, { "cpf" => "x" }).keys
      end

      # -- body --------------------------------------------------------------------------------------------

      def body_specs
        [Params.string(:key, required: true, max_length: 10), Params.decimal(:amount, max_length: 8),
         Params.boolean(:flag), Params.integer(:size, min: 1, max: 5), Params.string(:kind, enum: %w[a b], fold: :downcase)]
      end

      def test_body_values
        values = Params.from_body(body_specs, { "key" => "k", "amount" => 12.5, "flag" => false, "size" => 3, "kind" => "A" })
        assert_equal({ key: "k", amount: 12.5, flag: false, size: 3, kind: "a" }, values)
      end

      def test_decimal_accepts_numbers_and_strings
        [12, 12.5, "12,50", "0"].each do |amount|
          assert_equal amount, Params.from_body(body_specs, { "key" => "k", "amount" => amount })[:amount]
        end
      end

      def test_body_problems_are_422_validation_errors
        error = problem_for(body_specs, { "amount" => "1" }, kind: :body)
        assert_equal 422, error.status
        assert_equal "validation-error", error.slug
        assert_equal [["key", :missing]], codes(error)
      end

      def test_null_counts_as_absent
        assert_equal({ key: "k" }, Params.from_body(body_specs, { "key" => "k", "amount" => nil, "flag" => nil }))
        assert_equal [["key", :missing]], codes(problem_for(body_specs, { "key" => nil }, kind: :body))
      end

      def test_body_type_checks
        {
          "key" => [5, true, [], {}, 1.5], "amount" => [true, [], {}, Float::INFINITY, -Float::INFINITY],
          "flag" => ["true", 1, 0, "false"], "size" => ["3", 3.0, true, []], "kind" => [1, true]
        }.each do |field, values|
          values.each do |value|
            raw = { "key" => "k" }.merge(field => value)
            raw = { "key" => value } if field == "key"
            error = problem_for(body_specs, raw, kind: :body)
            assert_includes codes(error), [field, :invalid_type], "#{field}: #{value.inspect}"
          end
        end
      end

      def test_body_ranges_enums_and_lengths
        assert_equal [["size", :out_of_range]], codes(problem_for(body_specs, { "key" => "k", "size" => 6 }, kind: :body))
        assert_equal [["size", :out_of_range]], codes(problem_for(body_specs, { "key" => "k", "size" => 0 }, kind: :body))
        assert_equal [["kind", :not_allowed]], codes(problem_for(body_specs, { "key" => "k", "kind" => "z" }, kind: :body))
        assert_equal [["key", :too_long]], codes(problem_for(body_specs, { "key" => "k" * 11 }, kind: :body))
        assert_equal [["amount", :too_long]], codes(problem_for(body_specs, { "key" => "k", "amount" => "9" * 9 }, kind: :body))
      end

      def test_unknown_fields_are_rejected
        error = problem_for(body_specs, { "key" => "k", "ammount" => 1 }, kind: :body)
        assert_equal [["ammount", :unknown_field]], codes(error)
        assert_includes error.errors.first.message, "unknown field"
      end

      def test_param_is_immutable_and_documented_by_its_attributes
        param = Params.integer(:count, default: 1, min: 1, max: 9, description: "How many", example: 3)
        assert_predicate param, :frozen?
        assert_equal [:count, :integer, false, 1, 1, 9, 3],
                     [param.name, param.type, param.required, param.default, param.min, param.max, param.example]
        assert_equal "How many", param.description
      end
    end
  end
end
