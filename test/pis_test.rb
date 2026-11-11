# frozen_string_literal: true

require_relative "test_helper"

module Brkit
  class PISTest < Minitest::Test
    # 12345678919 is the sample used by published PIS validators (weighted sum 233, remainder 2, check digit 9);
    # 123.45678.90-0 is the worked example of a public PIS tool (sum 231, remainder 0). The rest come from an
    # independent implementation (Node.js, rule "11 - remainder, with 10 and 11 becoming 0").
    VALID = %w[
      12345678919 12345678900 11111111116
      60758446563 92996874528 01507638695 45075405881 02935983062 67681522314 48622717922 70205020276
    ].freeze

    INVALID = {
      "" => :blank,
      "123" => :invalid_length,
      "123456789191" => :invalid_length,
      "12345678918" => :checksum,
      "12345678910" => :checksum,
      "11111111111" => :repeated_digits,
      "00000000000" => :repeated_digits,
      "1234567891a" => :invalid_characters,
      "123/45678-91" => :invalid_characters
    }.freeze

    def test_known_valid_numbers
      VALID.each do |number|
        result = PIS.validate(number)
        assert_valid result, "#{number}: #{result.error_messages.inspect}"
        assert_equal number, result.normalized
      end
    end

    def test_known_invalid_numbers
      INVALID.each do |input, code|
        result = PIS.validate(input)
        refute_valid result, input.inspect
        assert_equal [code], result.errors.map(&:code), "#{input.inspect} => #{result.error_messages.inspect}"
      end
    end

    def test_punctuation
      ["123.45678.91-9", "12345678919", " 123 45678 91 9 ", "123.4567891-9"].each do |input|
        assert_valid PIS.validate(input), input
      end
      assert_equal "123.45678.91-9", PIS.validate("12345678919").formatted
      assert_equal "12345678919", PIS.validate("123.45678.91-9").normalized
    end

    def test_explain_for_a_remainder_of_two
      step = PIS.validate("12345678919", explain: true).details[:steps].first
      assert_equal [1, 2, 3, 4, 5, 6, 7, 8, 9, 1], step[:values]
      assert_equal [3, 2, 9, 8, 7, 6, 5, 4, 3, 2], step[:weights]
      assert_equal [3, 4, 27, 32, 35, 36, 35, 32, 27, 2], step[:products]
      assert_equal [233, 2, 9, 9, true], step.values_at(:sum, :remainder, :check_digit, :actual, :match)
    end

    def test_remainders_zero_and_one_give_check_digit_zero
      zero = PIS.validate("12345678900", explain: true).details[:steps].first
      assert_equal [231, 0, 0], zero.values_at(:sum, :remainder, :check_digit)
      one = (1..999).map { |n| "1234#{n.to_s.rjust(6, '0')}" }.find do |base|
        Mod11.step(values: base.chars.map(&:to_i), weights: PIS::WEIGHTS)[:remainder] == 1
      end
      refute_nil one
      assert_equal 0, PIS.check_digit(one.chars.map(&:to_i))
      assert_valid PIS.validate("#{one}0")
    end

    def test_a_failed_checksum_reports_expected_and_actual_digit
      result = PIS.validate("12345678918")
      assert_includes result.errors.first.message, "expected 9, got 8"
    end

    def test_format
      assert_equal "123.45678.91-9", PIS.format("12345678919")
      error = assert_raises(InvalidInputError) { PIS.format("1") }
      assert_equal [:invalid_length], error.issues.map(&:code)
    end

    def test_strip_and_predicates
      assert_equal "12345678919", PIS.strip("123.45678.91-9")
      assert PIS.valid?("12345678919")
      refute PIS.valid?("12345678918")
    end

    def test_generated_numbers_are_valid_and_reproducible
      200.times do |seed|
        pis = PIS.generate(seed: seed)
        assert_valid PIS.validate(pis), "seed #{seed}: #{pis}"
      end
      assert_equal PIS.generate(seed: 42), PIS.generate(seed: 42)
      assert_match(/\A\d{3}\.\d{5}\.\d{2}-\d\z/, PIS.generate(seed: 1, formatted: true))
      assert_raises(InvalidInputError) { PIS.generate(rng: Random.new(1), seed: 1) }
    end

    def test_degenerate_random_source
      error = assert_raises(Error) { PIS.generate(rng: ScriptedRng.new) }
      assert_includes error.message, "could not generate a PIS"
    end

    def test_boundaries
      assert_equal [:too_long], PIS.validate("1" * 257).errors.map(&:code)
      assert_error PIS.validate(nil), :blank
      assert_kind_of Result, PIS.validate("1234567891\xFF")
    end
  end
end
