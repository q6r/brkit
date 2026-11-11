# frozen_string_literal: true

require_relative "test_helper"

module Brkit
  class CardTest < Minitest::Test
    # Sandbox numbers published by payment processors, with the network they belong to.
    SANDBOX = {
      "visa" => %w[4111111111111111 4012888888881881 4222222222222],
      "mastercard" => %w[5555555555554444 5105105105105100 2223003122003222],
      "amex" => %w[378282246310005 371449635398431],
      "discover" => %w[6011111111111117 6011000990139424],
      "jcb" => %w[3530111333300000 3566002020360505],
      "diners" => %w[30569309025904 38520000023237]
    }.freeze

    # Leading digits taken from the public tables of the credit-card-type project (an independent source), padded
    # to 16 digits with zeros and completed with a Luhn digit before detection.
    BIN_PREFIXES = {
      "elo" => %w[401178 401179 438935 457631 457632 431274 451416 457393 504175 506699 506778 509000 509999 627780
                  636297 636368 650031 650033 650035 650051 650057 650081 650405 650439 650485 650538 650541 650598
                  650700 650718 650720 650727 650901 650978 651652 651679 651680 651704 655000 655019 655021 655058],
      "hipercard" => %w[606282],
      "hiper" => %w[637095 637568 637599 637609 637612],
      "amex" => %w[34 37],
      "diners" => %w[300 301 305 36 38 39],
      "jcb" => %w[3528 3550 3589],
      "mastercard" => %w[51 55 2221 2229 223 229 23 26 270 271 2720],
      "visa" => %w[4 41 49],
      "discover" => %w[6011 644 649 65],
      "unionpay" => %w[62 621 629]
    }.freeze

    NOT_THE_BRAND = {
      "mastercard" => %w[50 56 2220 2721 2800],
      "diners" => %w[299 306 37 35],
      "jcb" => %w[3527 3590],
      "discover" => %w[6010 643 66],
      "amex" => %w[33 35 36 38]
    }.freeze

    def number_with(prefix, length = 16)
      Luhn.complete(prefix.ljust(length - 1, "0"))
    end

    def test_published_sandbox_numbers
      SANDBOX.each do |brand, numbers|
        numbers.each do |number|
          result = Card.validate(number)
          assert_valid result, "#{number}: #{result.error_messages.inspect}"
          assert_equal brand, result.details[:brand], number
          assert_equal number, result.normalized
        end
      end
    end

    def test_test_numbers_constant
      Card::TEST_NUMBERS.each do |brand, number|
        assert_equal brand, Card.validate(number).details[:brand]
        assert Card.validate(number).details[:test_number]
      end
      assert_equal "4111111111111111", Card::TEST_NUMBERS["visa"]
      refute Card.validate(number_with("4123")).details[:test_number]
    end

    def test_brand_detection_by_prefix
      BIN_PREFIXES.each do |brand, prefixes|
        prefixes.each do |prefix|
          length = brand == "amex" ? 15 : 16
          detected = Card.detect(number_with(prefix, length))
          assert_equal brand, detected&.id, "prefix #{prefix} should be #{brand}"
        end
      end
    end

    def test_prefixes_just_outside_a_brand_range
      NOT_THE_BRAND.each do |brand, prefixes|
        prefixes.each do |prefix|
          detected = Card.detect(number_with(prefix))
          refute_equal brand, detected&.id, "prefix #{prefix} must not be #{brand}"
        end
      end
    end

    def test_elo_takes_precedence_over_visa_and_discover
      assert_equal "elo", Card.detect(number_with("401178")).id
      assert_equal "visa", Card.detect(number_with("401177")).id
      assert_equal "elo", Card.detect(number_with("650031")).id
      assert_equal "discover", Card.detect(number_with("650034")).id
    end

    def test_unknown_prefixes_have_no_brand
      assert_nil Card.detect(number_with("9"))
      assert_nil Card.detect("")
      assert_nil Card.detect(nil)
      assert_nil Card.validate(number_with("9")).details[:brand]
      assert_valid Card.validate(number_with("9")), "an unknown network is not an error"
    end

    def test_brands_list
      assert_equal %w[elo hipercard hiper amex diners jcb mastercard visa discover unionpay], Card.brands
      assert_equal Card.brands.length, Card::BRANDS.map(&:id).uniq.length
    end

    def test_invalid_numbers
      {
        "" => :blank,
        "4111 1111 1111 111x" => :invalid_characters,
        "4111/1111/1111/1111" => :invalid_characters,
        "4111111111" => :invalid_length,
        "41111111111111111111" => :invalid_length,
        "4111111111111112" => :luhn,
        "0000000000000000" => :repeated_digits
      }.each do |input, code|
        result = Card.validate(input)
        refute_valid result, input.inspect
        assert_includes result.errors.map(&:code), code, "#{input.inspect} => #{result.error_messages.inspect}"
      end
    end

    def test_each_failure_is_reported_once
      assert_equal [:luhn], Card.validate("4111111111111112").errors.map(&:code)
      assert_equal [:repeated_digits], Card.validate("0000000000000000").errors.map(&:code)
    end

    def test_brand_specific_lengths
      fourteen_digit_visa = number_with("4", 14)
      result = Card.validate(fourteen_digit_visa)
      assert_error result, :brand_length
      assert_includes result.error_messages.join, "Visa numbers have 13, 16, 18, 19 digits"
      assert_valid Card.validate(number_with("4", 13))
      assert_valid Card.validate(number_with("4", 19))
      assert_error Card.validate(number_with("34", 16)), :brand_length
      assert_error Card.validate(number_with("51", 15)), :brand_length
    end

    def test_length_boundaries
      assert_error Card.validate("1" * 11), :invalid_length
      assert_valid Card.validate(number_with("9", 12))
      assert_valid Card.validate(number_with("9", 19))
      assert_error Card.validate("1" * 20), :invalid_length
      assert_equal [:too_long], Card.validate("1" * 257).errors.map(&:code)
    end

    def test_separators_are_accepted
      ["4111 1111 1111 1111", "4111-1111-1111-1111", " 4111111111111111 "].each do |input|
        result = Card.validate(input)
        assert_valid result, input
        assert_equal "4111111111111111", result.normalized
      end
    end

    def test_details
      details = Card.validate("4111 1111 1111 1111").details
      assert_equal "visa", details[:brand]
      assert_equal "Visa", details[:brand_name]
      assert_equal 16, details[:length]
      assert details[:luhn]
      assert_equal "411111", details[:bin]
      assert_equal "1111", details[:last4]
      assert_equal "411111******1111", details[:masked]
      assert_equal 3, details[:cvv_length]
      assert_equal 4, Card.validate("378282246310005").details[:cvv_length]
    end

    def test_formatting_follows_the_network
      assert_equal "4111 1111 1111 1111", Card.validate("4111111111111111").formatted
      assert_equal "3782 822463 10005", Card.validate("378282246310005").formatted
      assert_equal "3056 930902 5904", Card.validate("30569309025904").formatted
      assert_equal "4111 1111 1111 1", Card.group("4111111111111", nil)
      assert_equal "4111 1111 1111 1", Card.group("4111111111111")
    end

    def test_mask
      assert_equal "411111******1111", Card.mask("4111111111111111")
      assert_equal "378282*****0005", Card.mask("378282246310005")
      assert_equal "1234567890", Card.mask("1234567890")
    end

    def test_explain_adds_the_luhn_walkthrough
      steps = Card.validate("4111111111111111", explain: true).details[:steps]
      assert_equal 16, steps[:entries].length
      assert_equal 0, steps[:remainder]
      refute Card.validate("4111111111111111").details.key?(:steps)
    end

    def test_generated_numbers_for_every_brand
      Card.brands.each do |brand|
        100.times do |seed|
          number = Card.generate(brand: brand, seed: seed)
          expected_length = Card::BRANDS.find { |candidate| candidate.id == brand }.lengths.first
          assert_equal expected_length, number.length, "#{brand} seed #{seed}"
          assert Luhn.valid?(number), "#{brand} seed #{seed}: #{number}"
          assert_equal brand, Card.detect(number).id, "#{brand} seed #{seed}: #{number}"
          assert_valid Card.validate(number)
        end
      end
    end

    def test_generation_options
      assert_match(/\A\d{4} \d{4} \d{4} \d{4}\z/, Card.generate(brand: "visa", seed: 1, formatted: true))
      assert_match(/\A\d{4} \d{6} \d{5}\z/, Card.generate(brand: :amex, seed: 1, formatted: true))
      assert_equal "visa", Card.detect(Card.generate(brand: "VISA", seed: 2)).id
      random_brand = Card.detect(Card.generate(seed: 3))
      assert_includes Card.brands, random_brand.id
    end

    def test_generation_rejects_an_unknown_brand
      error = assert_raises(InvalidInputError) { Card.generate(brand: "diners-club-x") }
      assert_equal [:unknown_brand], error.issues.map(&:code)
      assert_equal ["brand"], error.issues.map(&:field)
      assert_includes error.message, "visa"
    end

    def test_generation_is_reproducible
      assert_equal Card.generate(brand: "visa", seed: 42), Card.generate(brand: "visa", seed: 42)
      assert_equal "4637469267437721", Card.generate(brand: "visa", seed: 42)
      assert_equal Card.generate(seed: 9), Card.generate(seed: 9)
      assert_equal Card.generate(brand: "elo", rng: Random.new(4)), Card.generate(brand: "elo", seed: 4)
    end

    def test_generation_gives_up_when_the_brand_can_never_be_produced
      # a brand whose prefix is shadowed by a more specific one: all attempts are rejected
      shadowed = Card::Brand.new(id: "ghost", name: "Ghost", prefixes: [401_178], lengths: [16], cvv_length: 3,
                                 groups: [4, 4, 4, 4])
      error = assert_raises(Error) { Card.send(:random_number, Random.new(1), shadowed) }
      assert_includes error.message, "could not generate a Ghost number"
    end

    def test_never_raises_on_hostile_input
      ["4111\xFF1111", "\u0000", "4" * 5000, "４１１１１１１１１１１１１１１１"].each do |input|
        assert_kind_of Result, Card.validate(input)
      end
    end
  end
end
