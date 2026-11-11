# frozen_string_literal: true

require_relative "test_helper"

module Brkit
  class PhoneTest < Minitest::Test
    # The 67 area codes as published in a public DDD list (cross-checked with ANATEL's statement that Brazil has
    # 67 numbering areas).
    PUBLISHED_AREA_CODES = <<~LIST.tr("\n", " ")
      11 SP, 12 SP, 13 SP, 14 SP, 15 SP, 16 SP, 17 SP, 18 SP, 19 SP, 21 RJ, 22 RJ, 24 RJ, 27 ES, 28 ES, 31 MG, 32 MG,
      33 MG, 34 MG, 35 MG, 37 MG, 38 MG, 41 PR, 42 PR, 43 PR, 44 PR, 45 PR, 46 PR, 47 SC, 48 SC, 49 SC, 51 RS, 53 RS,
      54 RS, 55 RS, 61 DF, 62 GO, 63 TO, 64 GO, 65 MT, 66 MT, 67 MS, 68 AC, 69 RO, 71 BA, 73 BA, 74 BA, 75 BA, 77 BA,
      79 SE, 81 PE, 82 AL, 83 PB, 84 RN, 85 CE, 86 PI, 87 PE, 88 CE, 89 PI, 91 PA, 92 AM, 93 PA, 94 PA, 95 RR, 96 AP,
      97 AM, 98 MA, 99 MA
    LIST

    # input => [E.164, national notation, type]
    VALID = {
      "(11) 98765-4321" => ["+5511987654321", "(11) 98765-4321", "mobile"],
      "11987654321" => ["+5511987654321", "(11) 98765-4321", "mobile"],
      "(11)98765-4321" => ["+5511987654321", "(11) 98765-4321", "mobile"],
      "11 9 8765 4321" => ["+5511987654321", "(11) 98765-4321", "mobile"],
      "+55 11 98765-4321" => ["+5511987654321", "(11) 98765-4321", "mobile"],
      "+5511987654321" => ["+5511987654321", "(11) 98765-4321", "mobile"],
      "5511987654321" => ["+5511987654321", "(11) 98765-4321", "mobile"],
      "011 98765-4321" => ["+5511987654321", "(11) 98765-4321", "mobile"],
      "(11) 3456-7890" => ["+551134567890", "(11) 3456-7890", "landline"],
      "1134567890" => ["+551134567890", "(11) 3456-7890", "landline"],
      "+55 11 3456-7890" => ["+551134567890", "(11) 3456-7890", "landline"],
      "551134567890" => ["+551134567890", "(11) 3456-7890", "landline"],
      "01134567890" => ["+551134567890", "(11) 3456-7890", "landline"],
      "(61) 91234-5678" => ["+5561912345678", "(61) 91234-5678", "mobile"],
      "(85) 2345-6789" => ["+558523456789", "(85) 2345-6789", "landline"],
      "(21) 5555-5555" => ["+552155555555", "(21) 5555-5555", "landline"],
      "(21) 2000-0000" => ["+552120000000", "(21) 2000-0000", "landline"]
    }.freeze

    INVALID = {
      "" => :blank,
      "  " => :blank,
      "abc" => :invalid_characters,
      "11987654321x" => :invalid_characters,
      "(11) 98765-4321 ext 5" => :invalid_characters,
      "98765-4321" => :invalid_length,
      "3456-7890" => :invalid_length,
      "119876543210" => :invalid_length,
      "11 8765432" => :invalid_length,
      "(11) 98765-432" => :legacy_mobile,
      "(11) 8765-4321" => :legacy_mobile,
      "(11) 6765-4321" => :legacy_mobile,
      "(11) 9765-4321" => :legacy_mobile,
      "(11) 1234-5678" => :invalid_landline,
      "(11) 0234-5678" => :invalid_landline,
      "(11) 08765-4321" => :invalid_mobile,
      "(11) 88765-4321" => :invalid_mobile,
      "(11) 38765-4321" => :invalid_mobile,
      "(23) 98765-4321" => :invalid_area_code,
      "(10) 3456-7890" => :invalid_area_code,
      "(00) 3456-7890" => :invalid_area_code,
      "0800 123 4567" => :invalid_area_code,
      "+1 202 555 0100" => :foreign_number,
      "+44 20 7946 0958" => :foreign_number,
      "+" => :foreign_number,
      "+5" => :foreign_number
    }.freeze

    def test_published_area_code_list_matches
      published = PUBLISHED_AREA_CODES.split(", ").to_h { |pair| pair.split.then { |code, uf| [code, uf.strip] } }
      assert_equal 67, published.size
      assert_equal published, Phone::AREA_CODES
      assert_equal 67, Phone::AREA_CODES.size
    end

    def test_area_code_tables_agree
      assert_equal Phone::AREA_CODES_BY_UF.values.flatten.sort, Phone::AREA_CODES.keys
      assert_equal UF::CODES, Phone::AREA_CODES_BY_UF.keys.sort
      assert(Phone::AREA_CODES.values.all? { |uf| UF::CODES.include?(uf) })
    end

    def test_valid_numbers
      VALID.each do |input, (e164, national, type)|
        result = Phone.validate(input)
        assert_valid result, "#{input.inspect}: #{result.error_messages.inspect}"
        assert_equal e164, result.normalized, input
        assert_equal national, result.formatted, input
        assert_equal type, result.details[:type], input
      end
    end

    def test_invalid_numbers
      INVALID.each do |input, code|
        result = Phone.validate(input)
        refute_valid result, input.inspect
        assert_equal [code], result.errors.map(&:code), "#{input.inspect} => #{result.error_messages.inspect}"
        assert_nil result.normalized
      end
    end

    def test_details_of_a_mobile_number
      assert_equal({ area_code: "11", uf: "SP", number: "987654321", type: "mobile",
                     international: "+55 11 98765-4321" }, Phone.validate("(11) 98765-4321").details)
    end

    def test_details_of_a_landline
      assert_equal({ area_code: "11", uf: "SP", number: "34567890", type: "landline",
                     international: "+55 11 3456-7890" }, Phone.validate("(11) 3456-7890").details)
    end

    def test_every_area_code_accepts_mobile_and_landline_numbers
      Phone::AREA_CODES.each do |code, uf|
        mobile = Phone.validate("#{code}987654321")
        landline = Phone.validate("#{code}34567890")
        assert_valid mobile, code
        assert_valid landline, code
        assert_equal uf, mobile.details[:uf]
        assert_equal code, landline.details[:area_code]
      end
    end

    def test_country_code_55_is_not_confused_with_area_code_55
      # DDD 55 (Rio Grande do Sul) with and without the country code
      ["5532123456", "555532123456", "+55 55 3212-3456", "(55) 3212-3456"].each do |input|
        result = Phone.validate(input)
        assert_valid result, input
        assert_equal "+555532123456", result.normalized
        assert_equal "RS", result.details[:uf]
      end
      ["55998765432", "5555998765432", "(55) 99876-5432"].each do |input|
        assert_equal "+5555998765432", Phone.validate(input).normalized, input
      end
    end

    def test_trunk_prefix_is_only_removed_when_the_length_fits
      assert_valid Phone.validate("011987654321")
      assert_valid Phone.validate("01134567890")
      # ten digits starting with 0 are not "0 + 9 digits": the leading 01 is read as the area code
      assert_error Phone.validate("0119876543"), :invalid_area_code
    end

    def test_e164_and_format_helpers
      assert_equal "+5511987654321", Phone.e164("(11) 98765-4321")
      assert_nil Phone.e164("nope")
      assert_equal "(11) 98765-4321", Phone.format("+5511987654321")
      error = assert_raises(InvalidInputError) { Phone.format("123") }
      assert_equal [:invalid_length], error.issues.map(&:code)
    end

    def test_uf_for
      assert_equal "SP", Phone.uf_for("11")
      assert_equal "DF", Phone.uf_for("61")
      assert_nil Phone.uf_for("23")
      assert_nil Phone.uf_for(nil)
    end

    def test_boundaries_and_hostile_input
      assert_equal [:too_long], Phone.validate("1" * 257).errors.map(&:code)
      assert_error Phone.validate(nil), :blank
      assert_kind_of Result, Phone.validate("\xFF11987654321")
      assert_error Phone.validate("(11) 98765-4321‮"), :invalid_characters
    end

    def test_generated_mobile_numbers
      200.times do |seed|
        number = Phone.generate(seed: seed)
        result = Phone.validate(number)
        assert_valid result, "seed #{seed}: #{number}"
        assert_equal "mobile", result.details[:type]
        assert_equal number, result.normalized
      end
    end

    def test_generated_landline_numbers
      100.times do |seed|
        number = Phone.generate(seed: seed, type: :landline)
        assert_equal "landline", Phone.validate(number).details[:type], number
      end
    end

    def test_generation_options
      assert_equal "11", Phone.validate(Phone.generate(ddd: "11", seed: 1)).details[:area_code]
      assert_match(/\A\(21\) 9\d{4}-\d{4}\z/, Phone.generate(ddd: "21", seed: 1, formatted: true))
      40.times do |seed|
        area_code = Phone.validate(Phone.generate(uf: "ba", seed: seed)).details[:area_code]
        assert_includes Phone::AREA_CODES_BY_UF.fetch("BA"), area_code
      end
      assert_equal "mobile", Phone.validate(Phone.generate(seed: 3, type: "mobile")).details[:type]
    end

    def test_generation_rejects_bad_arguments
      assert_equal [:invalid_area_code], assert_raises(InvalidInputError) { Phone.generate(ddd: "23") }.issues.map(&:code)
      assert_equal [:unknown_uf], assert_raises(InvalidInputError) { Phone.generate(uf: "XX") }.issues.map(&:code)
      assert_equal [:invalid_type], assert_raises(InvalidInputError) { Phone.generate(type: :satellite) }.issues.map(&:code)
    end

    def test_generation_is_reproducible
      assert_equal Phone.generate(seed: 42), Phone.generate(seed: 42)
      assert_equal "+5583967469267", Phone.generate(seed: 42)
      assert_equal "(11) 4374-6926", Phone.generate(seed: 42, ddd: "11", type: :landline, formatted: true)
    end

    def test_json_friendly
      parsed = JSON.parse(JSON.generate(Phone.validate("(11) 98765-4321")))
      assert_equal "+5511987654321", parsed["normalized"]
      assert_equal "mobile", parsed["details"]["type"]
    end
  end
end
