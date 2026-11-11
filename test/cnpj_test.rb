# frozen_string_literal: true

require_relative "test_helper"

module Brkit
  class CNPJTest < Minitest::Test
    # Classic numbers: 11.222.333/0001-81 (the usual tutorial example, verified by hand), Banco do Brasil
    # (00.000.000/0001-91), Banco Central (00.038.166/0001-05, also the CNPJ key of the Pix manual) and numbers from an
    # independent implementation (Node.js).
    CLASSIC = %w[
      11222333000181 00000000000191 00038166000105
      40993383706420 98160128092992 37108283341274 74298715373568 65086964598924 17822483602501
      02836523242371 74902267280391
    ].freeze

    # 12ABC34501DE35 is the example of the Receita Federal "CNPJ alfanumérico" Q&A (written 12.ABC.345/01DE-35)
    # and the CNPJ key shown in the Banco Central Pix manual. The others come from the independent implementation.
    ALPHANUMERIC = %w[
      12ABC34501DE35
      O5T89HJ7AI0V00 7R63DH29DJ2Y82 9O2DS5DH8NNL60 VB9YNRLGVXCV88 2NNXWJOJ0WY403 6FE7FGGXD7ZU32 GTEMWGZ246YS56
      NFGIU6U7EEV864 COQWG1AEGB6S24 HGCWEJ2BZY0381
    ].freeze

    INVALID = {
      "" => :blank,
      " " => :blank,
      "123" => :invalid_length,
      "11.222.333/0001-8" => :invalid_length,
      "11.222.333/0001-811" => :invalid_length,
      "11.222.333/0001-82" => :checksum,
      "11.222.333/0001-91" => :checksum,
      "12.ABC.345/01DE-36" => :checksum,
      "12.ABC.345/01DE-25" => :checksum,
      "12.ABC.345/01DE-3A" => :invalid_check_digits,
      "12.ABC.345/01DE-AB" => :invalid_check_digits,
      "AAAAAAAAAAAAAA" => :invalid_check_digits,
      "12.AB!.345/01DE-35" => :invalid_characters,
      "12.ABC.345\\01DE-35" => :invalid_characters,
      "11.222.333/0001-81;" => :invalid_characters,
      "00000000000000" => :repeated_digits,
      "11111111111111" => :repeated_digits,
      "99.999.999/9999-99" => :repeated_digits
    }.freeze

    def test_known_valid_classic_numbers
      CLASSIC.each do |number|
        result = CNPJ.validate(number)
        assert_valid result, "#{number}: #{result.error_messages.inspect}"
        assert_equal number, result.normalized
        refute result.details[:alphanumeric], "#{number} has no letters"
      end
    end

    def test_known_valid_alphanumeric_numbers
      ALPHANUMERIC.each do |number|
        result = CNPJ.validate(number)
        assert_valid result, "#{number}: #{result.error_messages.inspect}"
        assert_equal number, result.normalized
        assert result.details[:alphanumeric], "#{number} has letters"
      end
    end

    def test_official_alphanumeric_sample
      result = CNPJ.validate("12.ABC.345/01DE-35")
      assert_valid result
      assert_equal "12ABC34501DE35", result.normalized
      assert_equal "12.ABC.345/01DE-35", result.formatted
      assert_equal "35", CNPJ.check_digits("12ABC34501DE")
    end

    def test_classic_sample_still_validates
      assert_valid CNPJ.validate("11.222.333/0001-81")
      assert_equal "81", CNPJ.check_digits("112223330001")
    end

    def test_known_invalid_numbers
      INVALID.each do |input, code|
        result = CNPJ.validate(input)
        refute_valid result, "#{input.inspect} should be invalid"
        assert_equal [code], result.errors.map(&:code), "#{input.inspect} => #{result.error_messages.inspect}"
      end
    end

    def test_lower_case_letters_are_accepted_and_normalised
      result = CNPJ.validate("12.abc.345/01de-35")
      assert_valid result
      assert_equal "12ABC34501DE35", result.normalized
      assert_equal "12.abc.345/01de-35", result.input
    end

    def test_accepts_any_punctuation_layout
      ["11.222.333/0001-81", "11222333000181", "11.222.333/000181", " 11 222 333 0001 81 ", "11222333/0001-81"].each do |input|
        assert_valid CNPJ.validate(input), input.inspect
      end
    end

    def test_letter_values_follow_the_ascii_offset
      assert_equal 48, CNPJ::ASCII_OFFSET
      steps = CNPJ.validate("12.ABC.345/01DE-35", explain: true).details[:steps]
      assert_equal [1, 2, 17, 18, 19, 3, 4, 5, 0, 1, 20, 21], steps.first[:values]
      assert_equal %w[1 2 A B C 3 4 5 0 1 D E], steps.first[:chars]
    end

    def test_explain_steps_for_the_alphanumeric_sample
      first, second = CNPJ.validate("12.ABC.345/01DE-35", explain: true).details[:steps]
      assert_equal [5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2], first[:weights]
      assert_equal [5, 8, 51, 36, 171, 24, 28, 30, 0, 4, 60, 42], first[:products]
      assert_equal [459, 8, 3, 3, true], first.values_at(:sum, :remainder, :check_digit, :actual, :match)
      assert_equal [6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2], second[:weights]
      assert_equal [6, 10, 68, 54, 38, 27, 32, 35, 0, 5, 80, 63, 6], second[:products]
      assert_equal [424, 6, 5, 5, true], second.values_at(:sum, :remainder, :check_digit, :actual, :match)
      assert_equal 13, second[:chars].length
    end

    def test_explain_steps_for_the_classic_sample
      first, second = CNPJ.validate("11.222.333/0001-81", explain: true).details[:steps]
      assert_equal [102, 3, 8], first.values_at(:sum, :remainder, :check_digit)
      assert_equal [120, 10, 1], second.values_at(:sum, :remainder, :check_digit)
    end

    def test_explain_is_off_by_default
      refute CNPJ.validate("11.222.333/0001-81").details.key?(:steps)
    end

    def test_details
      details = CNPJ.validate("12.ABC.345/01DE-35").details
      assert_equal({ root: "12ABC345", branch: "01DE", check_digits: "35", alphanumeric: true, headquarters: false },
                   details)
      head_office = CNPJ.validate("11.222.333/0001-81").details
      assert_equal "11222333", head_office[:root]
      assert head_office[:headquarters]
      refute head_office[:alphanumeric]
    end

    def test_check_digits_requires_twelve_alphanumeric_characters
      assert_equal "35", CNPJ.check_digits("12abc34501de")
      ["", "123", "12ABC34501DE3", "12ABC34501D!", "12.ABC.345/01D"].each do |base|
        error = assert_raises(InvalidInputError, base.inspect) { CNPJ.check_digits(base) }
        assert_equal [:invalid_base], error.issues.map(&:code)
      end
    end

    def test_format_and_strip
      assert_equal "12.ABC.345/01DE-35", CNPJ.format("12abc34501de35")
      assert_equal "11.222.333/0001-81", CNPJ.format("11222333000181")
      assert_equal "12ABC34501DE35", CNPJ.strip("12.abc.345/01de-35")
      error = assert_raises(InvalidInputError) { CNPJ.format("123") }
      assert_equal [:invalid_length], error.issues.map(&:code)
    end

    def test_boundaries
      assert_equal [:too_long], CNPJ.validate("1" * 257).errors.map(&:code)
      assert_equal [:invalid_length], CNPJ.validate("1" * 256).errors.map(&:code)
      assert_error CNPJ.validate(nil), :blank
      assert_valid CNPJ.validate(11_222_333_000_181)
    end

    def test_invalid_encodings_never_raise
      ["11222333000181\xFF", "\xFF", "11222333000181".b, "\u0000"].each do |input|
        assert_kind_of Result, CNPJ.validate(input)
      end
      assert_error CNPJ.validate("11222333000181\xFF"), :invalid_characters
    end

    def test_generated_classic_numbers
      200.times do |seed|
        cnpj = CNPJ.generate(seed: seed)
        assert_match(/\A\d{8}0001\d{2}\z/, cnpj)
        result = CNPJ.validate(cnpj)
        assert_valid result, "seed #{seed}: #{cnpj}"
        refute result.details[:alphanumeric]
      end
    end

    def test_generated_alphanumeric_numbers_always_contain_a_letter
      200.times do |seed|
        cnpj = CNPJ.generate(alphanumeric: true, seed: seed)
        result = CNPJ.validate(cnpj)
        assert_valid result, "seed #{seed}: #{cnpj}"
        assert result.details[:alphanumeric], "#{cnpj} should contain a letter"
        assert_match(/\A[0-9A-Z]{12}\d{2}\z/, cnpj)
      end
    end

    def test_generation_options
      assert_match(/\A\d{2}\.\d{3}\.\d{3}\/0001-\d{2}\z/, CNPJ.generate(seed: 1, formatted: true))
      assert_match(%r{\A[0-9A-Z]{2}\.[0-9A-Z]{3}\.[0-9A-Z]{3}/0002-\d{2}\z},
                   CNPJ.generate(seed: 1, formatted: true, branch: "0002"))
      assert_equal "A1B2", CNPJ.validate(CNPJ.generate(alphanumeric: true, branch: "a1b2", seed: 3)).details[:branch]
    end

    def test_generation_validates_the_branch
      ["1", "12345", "ABCD", "00-1", nil].each do |branch|
        error = assert_raises(InvalidInputError, branch.inspect) { CNPJ.generate(branch: branch) }
        assert_equal [:invalid_branch], error.issues.map(&:code)
      end
      assert_raises(InvalidInputError) { CNPJ.generate(alphanumeric: true, branch: "AB!D") }
    end

    def test_generation_is_reproducible
      assert_equal CNPJ.generate(seed: 42), CNPJ.generate(seed: 42)
      assert_equal CNPJ.generate(alphanumeric: true, seed: 42), CNPJ.generate(alphanumeric: true, seed: 42)
      assert_equal CNPJ.generate(rng: Random.new(8)), CNPJ.generate(seed: 8)
      assert_raises(InvalidInputError) { CNPJ.generate(rng: Random.new(1), seed: 1) }
    end

    def test_degenerate_random_sources
      assert_equal "00000000000191", CNPJ.generate(rng: ScriptedRng.new), "all-zero root with branch 0001 is Banco do Brasil"
      error = assert_raises(Error) { CNPJ.generate(branch: "0000", rng: ScriptedRng.new) }
      assert_includes error.message, "could not generate a CNPJ"
    end

    def test_changing_a_check_digit_always_invalidates
      200.times do |seed|
        cnpj = CNPJ.generate(alphanumeric: seed.odd?, seed: seed)
        [12, 13].each do |index|
          mutated = cnpj.dup
          mutated[index] = ((cnpj[index].to_i + 1 + (seed % 8)) % 10).to_s
          refute CNPJ.valid?(mutated), "#{mutated} (mutated from #{cnpj})"
        end
      end
    end
  end
end
