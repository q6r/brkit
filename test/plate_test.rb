# frozen_string_literal: true

require_relative "test_helper"

module Brkit
  class PlateTest < Minitest::Test
    LEGACY = ["ABC-1234", "abc1234", "ABC 1234", "XYZ-0000", " ABC-1234 ", "kfr-5090"].freeze
    MERCOSUL = %w[ABC1D23 abc1d23 BRA2E19 ABC1C34 ZZZ9Z99].freeze

    INVALID = {
      "" => :blank,
      "AB-1234" => :invalid_format,
      "ABCD123" => :invalid_format,
      "ABC-12345" => :invalid_format,
      "ABC-123" => :invalid_format,
      "1234-ABC" => :invalid_format,
      "ABC1D2" => :invalid_format,
      "ABC1DD3" => :invalid_format,
      "ABC12D3" => :invalid_format,
      "AB11D23" => :invalid_format,
      "AB€-1234" => :invalid_characters,
      "ÁBC-1234" => :invalid_characters,
      "ABC_1234" => :invalid_characters,
      "ABC.1234" => :invalid_characters
    }.freeze

    def test_legacy_plates
      LEGACY.each do |input|
        result = Plate.validate(input)
        assert_valid result, input
        assert_equal "legacy", result.details[:layout]
        assert_match(/\A[A-Z]{3}\d{4}\z/, result.normalized)
        assert_match(/\A[A-Z]{3}-\d{4}\z/, result.formatted)
      end
    end

    def test_mercosul_plates
      MERCOSUL.each do |input|
        result = Plate.validate(input)
        assert_valid result, input
        assert_equal "mercosul", result.details[:layout]
        assert_equal result.normalized, result.formatted
        assert_match(/\A[A-Z]{3}\d[A-Z]\d{2}\z/, result.normalized)
      end
    end

    def test_invalid_plates
      INVALID.each do |input, code|
        result = Plate.validate(input)
        refute_valid result, input.inspect
        assert_equal [code], result.errors.map(&:code), "#{input.inspect} => #{result.error_messages.inspect}"
      end
    end

    def test_normalisation
      result = Plate.validate(" abc-1234 ")
      assert_equal "ABC1234", result.normalized
      assert_equal "ABC-1234", result.formatted
      assert_equal " abc-1234 ", result.input
      assert_equal "ABC1D23", Plate.validate("abc 1d23").normalized
    end

    def test_digit_to_letter_mapping_is_a_to_j
      assert_equal "ABCDEFGHIJ", Plate::DIGIT_LETTERS.join
      (0..9).each do |digit|
        letter = %w[A B C D E F G H I J][digit]
        result = Plate.convert("ABC1#{digit}34")
        assert_valid result
        assert_equal "ABC1#{letter}34", result.normalized, "digit #{digit}"
        assert_equal({ position: 5, digit: digit.to_s, letter: letter }, result.details[:conversion])
      end
    end

    def test_published_conversion_example
      # Senatran/Contran: the legacy plate ABC 1234 becomes ABC1C34
      result = Plate.convert("ABC-1234")
      assert_equal "ABC1C34", result.normalized
      assert_equal "ABC1C34", result.formatted
      assert_equal "legacy", result.details[:from]
      assert_equal "mercosul", result.details[:layout]
      assert_equal "ABC1C34", Plate.validate("ABC-1234").details[:mercosul]
      assert_equal "KFR5A90", Plate.convert("KFR-5090").normalized
    end

    def test_converting_a_mercosul_plate_is_a_no_op
      result = Plate.convert("abc1d23")
      assert_valid result
      assert_equal "ABC1D23", result.normalized
      assert_equal "mercosul", result.details[:from]
      refute result.details.key?(:conversion)
    end

    def test_converting_an_invalid_plate_reports_the_problem
      result = Plate.convert("AB-1234")
      refute_valid result
      assert_error result, :invalid_format
      assert_nil result.normalized
    end

    def test_converted_plates_are_always_valid_mercosul_plates
      random = Random.new(3)
      300.times do
        legacy = Plate.generate(layout: :legacy, rng: random)
        converted = Plate.convert(legacy)
        assert_valid converted, legacy
        assert_equal "mercosul", Plate.validate(converted.normalized).details[:layout], legacy
        assert_equal legacy[0, 4], converted.normalized[0, 4]
        assert_equal legacy[5, 2], converted.normalized[5, 2]
      end
    end

    def test_to_mercosul
      assert_equal "ABC1C34", Plate.to_mercosul("ABC-1234")
      assert_equal "ABC1D23", Plate.to_mercosul("ABC1D23")
      error = assert_raises(InvalidInputError) { Plate.to_mercosul("nope!") }
      assert_equal [:invalid_characters], error.issues.map(&:code)
    end

    def test_strip_and_predicate
      assert_equal "ABC1234", Plate.strip(" abc-1234")
      assert Plate.valid?("ABC-1234")
      refute Plate.valid?("ABC-123")
    end

    def test_boundaries_and_hostile_input
      assert_equal [:too_long], Plate.validate("A" * 257).errors.map(&:code)
      assert_error Plate.validate(nil), :blank
      assert_kind_of Result, Plate.validate("ABC\xFF1234")
      assert_error Plate.validate("ABC\xFF1234"), :invalid_characters
      assert_valid Plate.validate("ABC1234\n")
    end

    def test_generated_plates
      200.times do |seed|
        mercosul = Plate.generate(seed: seed)
        legacy = Plate.generate(layout: "legacy", seed: seed)
        assert_equal "mercosul", Plate.validate(mercosul).details[:layout], mercosul
        assert_equal "legacy", Plate.validate(legacy).details[:layout], legacy
      end
    end

    def test_generation_options
      assert_match(/\A[A-Z]{3}-\d{4}\z/, Plate.generate(layout: :legacy, formatted: true, seed: 1))
      assert_match(/\A[A-Z]{3}\d[A-Z]\d{2}\z/, Plate.generate(layout: :mercosul, formatted: true, seed: 1))
      error = assert_raises(InvalidInputError) { Plate.generate(layout: :weird) }
      assert_equal [:invalid_layout], error.issues.map(&:code)
    end

    def test_generation_is_reproducible
      assert_equal Plate.generate(seed: 42), Plate.generate(seed: 42)
      assert_equal "GTO7U69", Plate.generate(seed: 42)
      assert_equal "GTO-7469", Plate.generate(layout: :legacy, seed: 42, formatted: true)
    end
  end
end
