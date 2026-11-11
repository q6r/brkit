# frozen_string_literal: true

require_relative "test_helper"

module Brkit
  class CPFTest < Minitest::Test
    # 529.982.247-25, 111.444.777-35 and 123.456.789-09 are the numbers every CPF tutorial uses (the first was also
    # verified by hand: sums 295 and 347). The rest come from an independent implementation (Node.js, formulation
    # dv = ((sum * 10) % 11) % 10).
    VALID = %w[
      52998224725 11144477735 12345678909
      28907151679 33719018903 90875825524 08414021670 15682575113 43183788373 49968850845 04097015567
      64731071348 04933300895
    ].freeze

    INVALID = {
      "" => :blank,
      "   " => :blank,
      "123" => :invalid_length,
      "1234567890" => :invalid_length,
      "123456789012" => :invalid_length,
      "529.982.247-2" => :invalid_length,
      "abc" => :invalid_characters,
      "529.982.247-2A" => :invalid_characters,
      "529/982.247-25" => :invalid_characters,
      "529.982.247-25;" => :invalid_characters,
      "٥٢٩٩٨٢٢٤٧٢٥" => :invalid_characters,
      "529.982.247-25 " => :invalid_characters,
      "529.982.247-26" => :checksum,
      "529.982.247-35" => :checksum,
      "123.456.789-00" => :checksum,
      "111.444.777-34" => :checksum,
      "000.000.000-00" => :repeated_digits,
      "111.111.111-11" => :repeated_digits,
      "99999999999" => :repeated_digits
    }.freeze

    def test_known_valid_numbers
      VALID.each do |number|
        result = CPF.validate(number)
        assert_valid result, "#{number}: #{result.error_messages.inspect}"
        assert_equal number, result.normalized
      end
    end

    def test_known_invalid_numbers
      INVALID.each do |input, code|
        result = CPF.validate(input)
        refute_valid result, "#{input.inspect} should be invalid"
        assert_equal [code], result.errors.map(&:code), "#{input.inspect} => #{result.error_messages.inspect}"
      end
    end

    def test_every_repeated_digit_number_is_rejected
      ("0".."9").each do |digit|
        number = digit * 11
        assert_error CPF.validate(number), :repeated_digits, "#{number} slipped through"
      end
    end

    def test_accepts_punctuation_and_surrounding_whitespace
      ["529.982.247-25", "52998224725", " 529.982.247-25 ", "529 982 247 25", "529.982.24725", "529982247-25",
       "529.982.247-25\n"].each do |input|
        assert_valid CPF.validate(input), input.inspect
      end
    end

    def test_normalized_and_formatted
      result = CPF.validate("529 982 247-25")
      assert_equal "52998224725", result.normalized
      assert_equal "529.982.247-25", result.formatted
      assert_equal "529 982 247-25", result.input
    end

    def test_normalized_is_present_for_a_checksum_failure_but_not_for_a_wrong_length
      assert_equal "52998224726", CPF.validate("529.982.247-26").normalized
      assert_equal "529.982.247-26", CPF.validate("529.982.247-26").formatted
      assert_nil CPF.validate("5299822472").normalized
      assert_nil CPF.validate("5299822472").formatted
    end

    def test_non_string_input
      assert_valid CPF.validate(52_998_224_725)
      assert_valid CPF.validate(:"52998224725")
      assert_error CPF.validate(nil), :blank
      assert_error CPF.validate(Object.new), :invalid_characters
    end

    def test_too_long_input_is_rejected_cheaply
      result = CPF.validate("1" * 10_000)
      assert_equal [:too_long], result.errors.map(&:code)
      assert_nil result.normalized
    end

    def test_boundary_length_of_input
      assert_equal [:invalid_length], CPF.validate("1" * 256).errors.map(&:code)
      assert_equal [:too_long], CPF.validate("1" * 257).errors.map(&:code)
    end

    def test_invalid_encodings_never_raise
      ["52998224725\xFF", "\xFF\xFE", "\x00\x01", "52998224725".b,
       "5299\u0000822472".dup.force_encoding("BINARY")].each do |input|
        result = CPF.validate(input)
        assert_kind_of Result, result
        assert_predicate result, :frozen?
      end
      assert_error CPF.validate("52998224725\xFF"), :invalid_characters
    end

    def test_checksum_messages_name_the_failing_digit
      result = CPF.validate("529.982.247-35")
      assert_equal 1, result.errors.length
      assert_includes result.errors.first.message, "first check digit"
      assert_includes result.errors.first.message, "expected 2, got 3"
      assert_equal 2, CPF.validate("529.982.247-99").errors.length
    end

    def test_region_details
      details = CPF.validate("529.982.247-25").details
      assert_equal 7, details[:region_digit]
      assert_equal %w[ES RJ], details[:ufs]
      assert_equal({ digit: 7, ufs: %w[ES RJ] }, CPF.region("529.982.247-25"))
      assert_nil CPF.region("123")
    end

    def test_every_region_digit_maps_to_known_states
      assert_equal((0..9).to_a, CPF::REGIONS.keys)
      assert_equal UF::CODES.sort, CPF::REGIONS.values.flatten.sort, "each UF belongs to exactly one fiscal region"
    end

    def test_published_region_table
      expected = { 0 => "RS", 1 => "DF GO MS MT TO", 2 => "AC AM AP PA RO RR", 3 => "CE MA PI", 4 => "AL PB PE RN",
                   5 => "BA SE", 6 => "MG", 7 => "ES RJ", 8 => "SP", 9 => "PR SC" }
      expected.each { |digit, ufs| assert_equal ufs.split.sort, CPF::REGIONS.fetch(digit).sort, "region #{digit}" }
    end

    def test_explain_returns_the_checksum_steps_as_plain_data
      result = CPF.validate("529.982.247-25", explain: true)
      first, second = result.details[:steps]
      assert_equal "first check digit", first[:label]
      assert_equal [5, 2, 9, 9, 8, 2, 2, 4, 7], first[:values]
      assert_equal %w[5 2 9 9 8 2 2 4 7], first[:chars]
      assert_equal [10, 9, 8, 7, 6, 5, 4, 3, 2], first[:weights]
      assert_equal [50, 18, 72, 63, 48, 10, 8, 12, 14], first[:products]
      assert_equal [295, 11, 9, 2, 2, true], first.values_at(:sum, :modulus, :remainder, :check_digit, :actual, :match)
      assert_equal [5, 2, 9, 9, 8, 2, 2, 4, 7, 2], second[:values]
      assert_equal [11, 10, 9, 8, 7, 6, 5, 4, 3, 2], second[:weights]
      assert_equal [347, 6, 5, 5, true], second.values_at(:sum, :remainder, :check_digit, :actual, :match)
    end

    def test_explain_shows_which_digit_failed
      steps = CPF.validate("529.982.247-26", explain: true).details[:steps]
      assert steps[0][:match]
      refute steps[1][:match]
      assert_equal [5, 6], steps[1].values_at(:check_digit, :actual)
    end

    def test_explain_is_off_by_default_and_json_friendly
      refute CPF.validate("529.982.247-25").details.key?(:steps)
      parsed = JSON.parse(JSON.generate(CPF.validate("529.982.247-25", explain: true)))
      assert_equal 295, parsed["details"]["steps"][0]["sum"]
    end

    def test_a_remainder_of_one_gives_check_digit_zero
      # 123.456.789-09: the first sum is 210 = 19 * 11 + 1, so the first check digit is 0, not 10
      step = CPF.validate("123.456.789-09", explain: true).details[:steps].first
      assert_equal [210, 1, 0], step.values_at(:sum, :remainder, :check_digit)
    end

    def test_a_remainder_of_zero_gives_check_digit_zero
      bases = (1..999).map { |number| number.to_s.rjust(9, "0") }.select do |base|
        Mod11.step(values: base.chars.map(&:to_i), weights: CPF::FIRST_WEIGHTS)[:remainder].zero?
      end
      refute_empty bases
      bases.first(20).each do |base|
        number = base + CPF.check_digits(base.chars.map(&:to_i)).join
        assert_equal 0, number[9].to_i
        assert_valid CPF.validate(number)
      end
    end

    def test_format
      assert_equal "529.982.247-25", CPF.format("52998224725")
      assert_equal "529.982.247-25", CPF.format("529.982.247-25")
      error = assert_raises(InvalidInputError) { CPF.format("123") }
      assert_equal [:invalid_length], error.issues.map(&:code)
    end

    def test_strip
      assert_equal "52998224725", CPF.strip("529.982.247-25")
      assert_equal "", CPF.strip(nil)
      assert_equal "123", CPF.strip("a1b2c3")
    end

    def test_valid_predicate
      assert CPF.valid?("529.982.247-25")
      refute CPF.valid?("529.982.247-26")
    end

    def test_generated_numbers_are_valid
      300.times do |seed|
        cpf = CPF.generate(seed: seed)
        assert_match(/\A\d{11}\z/, cpf)
        assert_valid CPF.validate(cpf), "seed #{seed} gave #{cpf}"
      end
    end

    def test_generated_numbers_can_be_formatted
      cpf = CPF.generate(seed: 1, formatted: true)
      assert_match(/\A\d{3}\.\d{3}\.\d{3}-\d{2}\z/, cpf)
      assert_valid CPF.validate(cpf)
    end

    def test_generated_numbers_carry_the_requested_state
      UF::CODES.each do |uf|
        cpf = CPF.generate(uf: uf, seed: 99)
        assert_valid CPF.validate(cpf)
        assert_includes CPF.region(cpf)[:ufs], uf
      end
      assert_includes CPF.region(CPF.generate(uf: "sp", seed: 5))[:ufs], "SP"
    end

    def test_unknown_state_is_rejected
      error = assert_raises(InvalidInputError) { CPF.generate(uf: "XX") }
      assert_equal [:unknown_uf], error.issues.map(&:code)
    end

    def test_generation_is_reproducible
      assert_equal CPF.generate(seed: 42), CPF.generate(seed: 42)
      assert_equal CPF.generate(rng: Random.new(5)), CPF.generate(seed: 5)
      distinct = (0...20).map { |seed| CPF.generate(seed: seed) }.uniq.length
      assert_operator distinct, :>=, 19
    end

    def test_generation_rejects_conflicting_randomness
      assert_raises(InvalidInputError) { CPF.generate(rng: Random.new(1), seed: 1) }
    end

    def test_generation_skips_repeated_digit_bases
      # the first nine draws are all zeros (rejected); the next nine are a normal base
      rng = ScriptedRng.new(*([0] * 9), 5, 2, 9, 9, 8, 2, 2, 4, 7)
      assert_equal "52998224725", CPF.generate(rng: rng)
    end

    def test_generation_gives_up_on_a_degenerate_random_source
      error = assert_raises(Error) { CPF.generate(rng: ScriptedRng.new) }
      assert_includes error.message, "could not generate a CPF"
    end

    def test_changing_a_check_digit_always_invalidates
      200.times do |seed|
        cpf = CPF.generate(seed: seed)
        [9, 10].each do |index|
          mutated = cpf.dup
          mutated[index] = ((cpf[index].to_i + 1 + (seed % 8)) % 10).to_s
          refute CPF.valid?(mutated), "#{mutated} (mutated from #{cpf})"
        end
      end
    end

    def test_validation_never_raises_on_random_input
      random = Random.new(11)
      300.times do
        input = Array.new(random.rand(0..30)) { random.rand(256).chr }.join
        assert_kind_of Result, CPF.validate(input)
      end
    end
  end
end
