# frozen_string_literal: true

require_relative "test_helper"

module Brkit
  class CEPTest < Minitest::Test
    # Prefix ranges per state as published by Correios (via the public CEP table), written with the sub-ranges the
    # table uses. They must merge into the library's ranges.
    PUBLISHED = <<~TABLE
      AC 69900-69999
      AL 57000-57999
      AM 69000-69099 69100-69299 69400-69899
      AP 68900-68999
      BA 40000-42599 42600-43999 44000-48999
      CE 60000-61599 61600-61999 62000-63999
      DF 70000-70999 71000-72799 73000-73699
      ES 29000-29099 29100-29199 29200-29999
      GO 72800-72999 73700-73999 74000-74899 74900-75199 75200-76799
      MA 65000-65099 65100-65999
      MG 30000-31999 32000-34999 35000-39999
      MS 79000-79129 79130-79999
      MT 78000-78109 78110-78999
      PA 66000-66999 67000-67999 68000-68899
      PB 58000-58099 58100-58999
      PE 50000-52999 53000-54999 55000-56999
      PI 64000-64099 64100-64999
      PR 80000-82999 83000-83899 83900-87999
      RJ 20000-23799 23800-26599 26600-28999
      RN 59000-59139 59140-59999
      RO 76800-76849 76850-76999
      RR 69300-69339 69340-69399
      RS 90000-91999 92000-94999 95000-99999
      SC 88000-88099 88100-88179 88180-89999
      SE 49000-49099 49100-49999
      SP 01000-05999 06000-07999 08000-08499 08500-09999 11000-11999 12000-19999
      TO 77000-77299 77300-77999
    TABLE

    VALID = {
      "01310-100" => "01310100",
      "01310100" => "01310100",
      "01.310-100" => "01310100",
      " 01310-100 " => "01310100",
      "70040-010" => "70040010",
      "01000-000" => "01000000",
      "99999-999" => "99999999"
    }.freeze

    INVALID = {
      "" => :blank,
      "   " => :blank,
      "1234" => :invalid_length,
      "123456789" => :invalid_length,
      "01310-10" => :invalid_length,
      "00000-000" => :unassigned_prefix,
      "00999-999" => :unassigned_prefix,
      "abcde-fgh" => :invalid_characters,
      "01310/100" => :invalid_characters,
      "01310-100 " => :invalid_characters
    }.freeze

    def merged_published
      PUBLISHED.each_line.to_h do |line|
        uf, *parts = line.split
        ranges = parts.map { |part| part.split("-").map(&:to_i) }.sort
        merged = ranges.each_with_object([]) do |(from, to), list|
          if list.any? && list.last[1] + 1 == from
            list.last[1] = to
          else
            list << [from, to]
          end
        end
        [uf, merged]
      end
    end

    def test_ranges_match_the_published_table
      assert_equal merged_published, CEP::RANGES
    end

    def test_ranges_are_disjoint_and_well_formed
      all = CEP::RANGES.flat_map { |uf, ranges| ranges.map { |from, to| [from, to, uf] } }.sort
      all.each { |from, to, uf| assert_operator from, :<=, to, uf }
      all.each_cons(2) { |left, right| assert_operator left[1], :<, right[0], "#{left.last} overlaps #{right.last}" }
      assert_equal UF::CODES, CEP::RANGES.keys.sort
    end

    def test_valid_codes
      VALID.each do |input, digits|
        result = CEP.validate(input)
        assert_valid result, "#{input.inspect}: #{result.error_messages.inspect}"
        assert_equal digits, result.normalized
        assert_equal "#{digits[0, 5]}-#{digits[5, 3]}", result.formatted
      end
    end

    def test_invalid_codes
      INVALID.each do |input, code|
        result = CEP.validate(input)
        refute_valid result, input.inspect
        assert_equal [code], result.errors.map(&:code), "#{input.inspect} => #{result.error_messages.inspect}"
      end
    end

    def test_details
      assert_equal({ region_digit: 0, uf: "SP" }, CEP.validate("01310-100").details)
      assert_equal({ region_digit: 7, uf: "DF" }, CEP.validate("70040-010").details)
      assert_nil CEP.validate("10000-000").details[:uf]
    end

    def test_uf_lookup_at_range_borders
      {
        "01000" => "SP", "09999" => "SP", "10000" => nil, "10999" => nil, "11000" => "SP", "19999" => "SP",
        "20000" => "RJ", "28999" => "RJ", "29000" => "ES", "29999" => "ES", "30000" => "MG", "39999" => "MG",
        "40000" => "BA", "48999" => "BA", "49000" => "SE", "50000" => "PE", "57000" => "AL", "58000" => "PB",
        "59000" => "RN", "60000" => "CE", "64000" => "PI", "65000" => "MA", "66000" => "PA", "68899" => "PA",
        "68900" => "AP", "69000" => "AM", "69300" => "RR", "69400" => "AM", "69900" => "AC", "70000" => "DF",
        "72799" => "DF", "72800" => "GO", "72999" => "GO", "73000" => "DF", "73699" => "DF", "73700" => "GO",
        "76799" => "GO", "76800" => "RO", "76999" => "RO", "77000" => "TO", "78000" => "MT", "78999" => "MT",
        "79000" => "MS", "80000" => "PR", "87999" => "PR", "88000" => "SC", "90000" => "RS", "99999" => "RS",
        "00999" => nil
      }.each { |prefix, uf| assert_value uf, CEP.uf_for(prefix), prefix }
    end

    def test_uf_lookup_input_forms
      assert_equal "SP", CEP.uf_for("01310-100")
      assert_equal "SP", CEP.uf_for("01310")
      assert_nil CEP.uf_for("0131")
      assert_nil CEP.uf_for(nil)
    end

    def test_format_and_strip
      assert_equal "01310-100", CEP.format("01310100")
      assert_equal "01310-100", CEP.format("01.310-100")
      assert_equal "01310100", CEP.strip("01310-100")
      error = assert_raises(InvalidInputError) { CEP.format("123") }
      assert_equal [:invalid_length], error.issues.map(&:code)
    end

    def test_valid_predicate_and_boundaries
      assert CEP.valid?("01310-100")
      refute CEP.valid?("x")
      assert_equal [:too_long], CEP.validate("1" * 257).errors.map(&:code)
      assert_error CEP.validate(nil), :blank
      assert_kind_of Result, CEP.validate("0131\xFF100")
    end

    def test_generated_codes_are_valid_and_inside_the_requested_state
      UF::CODES.each do |uf|
        5.times do |seed|
          cep = CEP.generate(uf: uf, seed: seed)
          assert_match(/\A\d{8}\z/, cep)
          assert_valid CEP.validate(cep), "#{uf} seed #{seed}: #{cep}"
          assert_equal uf, CEP.uf_for(cep), "#{cep} should belong to #{uf}"
        end
      end
    end

    def test_generated_codes_without_a_state
      200.times do |seed|
        cep = CEP.generate(seed: seed)
        assert_valid CEP.validate(cep), cep
        refute_nil CEP.uf_for(cep), cep
      end
    end

    def test_generation_options_and_reproducibility
      assert_match(/\A\d{5}-\d{3}\z/, CEP.generate(seed: 1, formatted: true))
      assert_equal "SP", CEP.uf_for(CEP.generate(uf: "sp", seed: 1))
      assert_equal CEP.generate(seed: 42), CEP.generate(seed: 42)
      assert_equal "70795860", CEP.generate(seed: 42)
      assert_equal "17795-860", CEP.generate(seed: 42, uf: "SP", formatted: true)
      assert_equal [:unknown_uf], assert_raises(InvalidInputError) { CEP.generate(uf: "XX") }.issues.map(&:code)
    end
  end
end
