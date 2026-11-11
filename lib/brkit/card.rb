# frozen_string_literal: true

require_relative "luhn"
require_relative "result"
require_relative "rng"
require_relative "text"

module Brkit
  # Payment card numbers (PANs): Luhn validation, brand detection and test-number generation.
  #
  # Brand detection is range based (the leading digits, "IIN/BIN") and therefore a hint, not proof that a
  # card exists. The tables cover the networks common in Brazil (Visa, Mastercard, Elo, Hipercard, Hiper,
  # American Express, Diners Club) plus Discover, JCB and UnionPay, and were cross-checked against the
  # public tables of the +credit-card-type+ project. Issuers add ranges over time.
  #
  # Generated numbers are Luhn-valid and carry a real brand prefix but are random: use them only for
  # tests. Never send real card numbers to a test tool.
  module Card
    # A card network.
    #
    # @!attribute [r] id
    #   @return [String] lower-case identifier such as +"visa"+
    # @!attribute [r] name
    #   @return [String] display name
    # @!attribute [r] prefixes
    #   @return [Array<Integer, Range>] leading-digit patterns; a Range matches numbers of the same width
    # @!attribute [r] lengths
    #   @return [Array<Integer>] accepted PAN lengths; the first is used by the generator
    # @!attribute [r] cvv_length
    #   @return [Integer] security-code length
    # @!attribute [r] groups
    #   @return [Array<Integer>] display grouping for the first length
    Brand = Struct.new(:id, :name, :prefixes, :lengths, :cvv_length, :groups, keyword_init: true) do
      # @return [Boolean] true when +digits+ starts with one of the brand's prefixes
      def prefix?(digits)
        prefixes.any? do |spec|
          range = spec.is_a?(Range) ? spec : (spec..spec)
          width = range.begin.to_s.length
          digits.length >= width && range.cover?(digits[0, width].to_i)
        end
      end
    end

    # Ordered by specificity: narrow ranges (Elo, Hiper) must be tried before the broad ones they overlap.
    BRANDS = [
      Brand.new(id: "elo", name: "Elo", lengths: [16], cvv_length: 3, groups: [4, 4, 4, 4],
                prefixes: [401_178, 401_179, 438_935, 457_631, 457_632, 431_274, 451_416, 457_393, 504_175,
                           506_699..506_778, 509_000..509_999, 627_780, 636_297, 636_368, 650_031..650_033,
                           650_035..650_051, 650_057..650_081, 650_405..650_439, 650_485..650_538,
                           650_541..650_598, 650_700..650_718, 650_720..650_727, 650_901..650_978,
                           651_652..651_679, 651_680..651_704, 655_000..655_019, 655_021..655_058]),
      Brand.new(id: "hipercard", name: "Hipercard", lengths: [16], cvv_length: 3, groups: [4, 4, 4, 4],
                prefixes: [606_282]),
      Brand.new(id: "hiper", name: "Hiper", lengths: [16], cvv_length: 3, groups: [4, 4, 4, 4],
                prefixes: [637_095, 63_737_423, 63_743_358, 637_568, 637_599, 637_609, 637_612]),
      Brand.new(id: "amex", name: "American Express", lengths: [15], cvv_length: 4, groups: [4, 6, 5],
                prefixes: [34, 37]),
      Brand.new(id: "diners", name: "Diners Club", lengths: [14, 16, 19], cvv_length: 3, groups: [4, 6, 4],
                prefixes: [300..305, 36, 38, 39]),
      Brand.new(id: "jcb", name: "JCB", lengths: [16, 17, 18, 19], cvv_length: 3, groups: [4, 4, 4, 4],
                prefixes: [3528..3589]),
      Brand.new(id: "mastercard", name: "Mastercard", lengths: [16], cvv_length: 3, groups: [4, 4, 4, 4],
                prefixes: [51..55, 2221..2229, 223..229, 23..26, 270..271, 2720]),
      Brand.new(id: "visa", name: "Visa", lengths: [16, 13, 18, 19], cvv_length: 3, groups: [4, 4, 4, 4],
                prefixes: [4]),
      Brand.new(id: "discover", name: "Discover", lengths: [16, 19], cvv_length: 3, groups: [4, 4, 4, 4],
                prefixes: [6011, 644..649, 65]),
      Brand.new(id: "unionpay", name: "UnionPay", lengths: [16, 17, 18, 19], cvv_length: 3, groups: [4, 4, 4, 4],
                prefixes: [62])
    ].freeze

    # Number lengths accepted before the brand is considered (ISO/IEC 7812 allows up to 19 digits).
    LENGTH_RANGE = (12..19)

    # Widely published sandbox numbers, one per brand where one is well known.
    TEST_NUMBERS = {
      "visa" => "4111111111111111",
      "mastercard" => "5555555555554444",
      "amex" => "378282246310005",
      "discover" => "6011111111111117",
      "jcb" => "3530111333300000",
      "diners" => "30569309025904"
    }.freeze

    FORBIDDEN = /[^0-9\-\s]/

    class << self
      # @return [Array<String>] ids of the supported brands
      def brands
        BRANDS.map(&:id)
      end

      # Detects the network from the leading digits.
      #
      # @param number [String] digits (punctuation is ignored)
      # @return [Brand, nil]
      def detect(number)
        digits = Text.coerce(number).gsub(/\D/, "")
        BRANDS.find { |brand| brand.prefix?(digits) }
      end

      # Validates a card number: characters, length, brand length, repeated digits and Luhn.
      #
      # @param input [String] digits, optionally grouped with spaces or dashes
      # @param explain [Boolean] add the Luhn walk-through to +details[:steps]+
      # @return [Result] +details+ has +:brand+, +:brand_name+, +:length+, +:luhn+, +:bin+, +:last4+,
      #   +:masked+, +:cvv_length+ and +:test_number+
      def validate(input, explain: false)
        text = Text.coerce(input)
        problem = shape_problem(text)
        return failure(text, nil, problem) if problem

        digits = text.gsub(/\D/, "")
        return failure(text, digits, length_issue(digits)) unless LENGTH_RANGE.cover?(digits.length)

        brand = detect(digits)
        details = describe(digits, brand)
        details[:steps] = Luhn.steps(digits) if explain
        Result.new(kind: "card", input: text, normalized: digits, formatted: group(digits, brand),
                   errors: problems(digits, brand), details: details)
      end

      # @return [Boolean] shorthand for +validate(input).valid?+
      def valid?(input)
        validate(input).valid?
      end

      # Generates a Luhn-valid number with a real prefix of +brand+. It is random: use it for tests only.
      #
      # @param brand [String, Symbol, nil] one of {.brands}; random when nil
      # @param formatted [Boolean] group the digits
      # @param rng [#rand, nil] random source (see {Rng})
      # @param seed [Integer, nil] seed for a reproducible result
      # @return [String]
      # @raise [InvalidInputError] for an unknown brand
      def generate(brand: nil, formatted: false, rng: nil, seed: nil)
        random = Rng.resolve(rng: rng, seed: seed)
        network = brand.nil? ? Rng.pick(random, BRANDS) : find_brand(brand)
        number = random_number(random, network)
        formatted ? group(number, network) : number
      end

      # @param number [String] digits only
      # @param brand [Brand, nil]
      # @return [String] digits in groups (+"4111 1111 1111 1111"+)
      def group(number, brand = detect(number))
        sizes = brand&.groups
        return number.scan(/\d{1,4}/).join(" ") unless sizes && sizes.sum == number.length

        chunks = []
        sizes.inject(0) do |offset, size|
          chunks << number[offset, size]
          offset + size
        end
        chunks.join(" ")
      end

      # @param number [String] digits only
      # @return [String] first six and last four digits visible, the rest replaced by asterisks
      def mask(number)
        return number if number.length <= 10

        "#{number[0, 6]}#{'*' * (number.length - 10)}#{number[-4, 4]}"
      end

      private

      def failure(text, digits, issue)
        Result.new(kind: "card", input: text, normalized: digits, errors: [issue])
      end

      def shape_problem(text)
        if text.strip.empty?
          Issue.new(code: :blank, message: "card number is empty")
        elsif text.length > Text::MAX_INPUT_LENGTH
          Issue.new(code: :too_long, message: "input is longer than #{Text::MAX_INPUT_LENGTH} characters")
        elsif text.match?(FORBIDDEN)
          Issue.new(code: :invalid_characters,
                    message: "only digits, spaces and dashes are allowed (found #{Text.describe_chars(text, FORBIDDEN)})")
        end
      end

      def length_issue(digits)
        Issue.new(code: :invalid_length,
                  message: "a card number has #{LENGTH_RANGE.min} to #{LENGTH_RANGE.max} digits, got #{digits.length}")
      end

      def describe(digits, brand)
        {
          brand: brand&.id, brand_name: brand&.name, length: digits.length, luhn: Luhn.valid?(digits),
          bin: digits[0, 6], last4: digits[-4, 4], masked: mask(digits), cvv_length: brand&.cvv_length,
          test_number: TEST_NUMBERS.value?(digits)
        }
      end

      def problems(digits, brand)
        issues = []
        if brand && !brand.lengths.include?(digits.length)
          issues << Issue.new(code: :brand_length,
                              message: "#{brand.name} numbers have #{brand.lengths.sort.join(', ')} digits, got #{digits.length}")
        end
        issues << Issue.new(code: :repeated_digits, message: "all digits are the same") if digits.squeeze.length == 1
        issues << Issue.new(code: :luhn, message: "Luhn check failed") unless Luhn.valid?(digits)
        issues
      end

      def find_brand(brand)
        id = brand.to_s.downcase
        BRANDS.find { |candidate| candidate.id == id } ||
          raise(InvalidInputError.for(:unknown_brand, "unknown brand #{id[0, 24].inspect}; use one of #{brands.join(', ')}",
                                      field: "brand"))
      end

      # Draws random digits after a random prefix until the result is detected as +network+
      # (a Visa-looking prefix can fall into an Elo range).
      def random_number(random, network)
        length = network.lengths.first
        Rng.attempt("a #{network.name} number") do
          prefix = random_prefix(random, network)
          number = Luhn.complete(prefix + Rng.digits(random, length - 1 - prefix.length).join)
          number if detect(number)&.id == network.id
        end
      end

      def random_prefix(random, network)
        spec = Rng.pick(random, network.prefixes)
        (spec.is_a?(Range) ? random.rand(spec) : spec).to_s
      end
    end
  end
end
