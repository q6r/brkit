# frozen_string_literal: true

require_relative "result"
require_relative "rng"
require_relative "text"
require_relative "uf"

module Brkit
  # CEP (Código de Endereçamento Postal), the 8-digit Brazilian postal code, written +NNNNN-NNN+.
  #
  # Validation checks the shape only: there is no lookup and no claim that the
  # code is assigned to a street. As a convenience {RANGES} maps the first five
  # digits to the state that owns them; the table follows the prefix ranges
  # published by Correios and is approximate near range borders.
  module CEP
    LENGTH = 8
    FORBIDDEN = /[^0-9.\-\s]/

    # State => inclusive ranges of 5-digit prefixes.
    RANGES = {
      "AC" => [[69_900, 69_999]],
      "AL" => [[57_000, 57_999]],
      "AM" => [[69_000, 69_299], [69_400, 69_899]],
      "AP" => [[68_900, 68_999]],
      "BA" => [[40_000, 48_999]],
      "CE" => [[60_000, 63_999]],
      "DF" => [[70_000, 72_799], [73_000, 73_699]],
      "ES" => [[29_000, 29_999]],
      "GO" => [[72_800, 72_999], [73_700, 76_799]],
      "MA" => [[65_000, 65_999]],
      "MG" => [[30_000, 39_999]],
      "MS" => [[79_000, 79_999]],
      "MT" => [[78_000, 78_999]],
      "PA" => [[66_000, 68_899]],
      "PB" => [[58_000, 58_999]],
      "PE" => [[50_000, 56_999]],
      "PI" => [[64_000, 64_999]],
      "PR" => [[80_000, 87_999]],
      "RJ" => [[20_000, 28_999]],
      "RN" => [[59_000, 59_999]],
      "RO" => [[76_800, 76_999]],
      "RR" => [[69_300, 69_399]],
      "RS" => [[90_000, 99_999]],
      "SC" => [[88_000, 89_999]],
      "SE" => [[49_000, 49_999]],
      "SP" => [[1_000, 9_999], [11_000, 19_999]],
      "TO" => [[77_000, 77_999]]
    }.freeze

    class << self
      # Validates the shape of a CEP written with or without punctuation.
      #
      # @param input [String] e.g. +"01310-100"+, +"01310100"+ or +"01.310-100"+
      # @return [Result] +details+ has +:region_digit+ and +:uf+ (nil when the prefix is in no known range)
      def validate(input)
        text = Text.coerce(input)
        problem = shape_problem(text)
        return failure(text, nil, problem) if problem

        digits = strip(text)
        return failure(text, nil, length_issue(digits)) unless digits.length == LENGTH
        return failure(text, digits, unassigned_issue) if digits[0, 5].to_i < 1_000

        Result.new(kind: "cep", input: text, normalized: digits, formatted: mask(digits),
                   details: { region_digit: digits[0].to_i, uf: uf_for(digits) })
      end

      # @return [Boolean] shorthand for +validate(input).valid?+
      def valid?(input)
        validate(input).valid?
      end

      # @return [String] the digits of +input+ with all punctuation removed
      def strip(input)
        Text.coerce(input).gsub(/\D/, "")
      end

      # Applies the +NNNNN-NNN+ mask.
      #
      # @param input [String] exactly 8 digits once punctuation is removed
      # @return [String]
      # @raise [InvalidInputError] when +input+ does not hold 8 digits
      def format(input)
        digits = strip(input)
        raise InvalidInputError.new([length_issue(digits)]) unless digits.length == LENGTH

        mask(digits)
      end

      # @param input [String] a CEP, or at least its first five digits
      # @return [String, nil] the state whose prefix range contains the CEP
      def uf_for(input)
        prefix = strip(input)[0, 5]
        return nil if prefix.length < 5

        number = prefix.to_i
        RANGES.each { |uf, ranges| return uf if ranges.any? { |from, to| number.between?(from, to) } }
        nil
      end

      # Generates a CEP with a plausible prefix. It is not a lookup: the code is usually not assigned to a street.
      #
      # @param uf [String, nil] state to draw the prefix from; any state when nil
      # @param formatted [Boolean] apply the mask
      # @param rng [#rand, nil] random source (see {Rng})
      # @param seed [Integer, nil] seed for a reproducible result
      # @return [String]
      # @raise [InvalidInputError] for an unknown +uf+
      def generate(uf: nil, formatted: false, rng: nil, seed: nil)
        random = Rng.resolve(rng: rng, seed: seed)
        ranges = uf ? RANGES.fetch(UF.fetch(uf)) : RANGES.values.flatten(1)
        prefix = prefix_at(ranges, random.rand(ranges.sum { |from, to| to - from + 1 }))
        digits = prefix.to_s.rjust(5, "0") + random.rand(1_000).to_s.rjust(3, "0")
        formatted ? mask(digits) : digits
      end

      private

      def mask(digits)
        "#{digits[0, 5]}-#{digits[5, 3]}"
      end

      def failure(text, digits, issue)
        Result.new(kind: "cep", input: text, normalized: digits&.length == LENGTH ? digits : nil,
                   formatted: digits&.length == LENGTH ? mask(digits) : nil, errors: [issue])
      end

      def shape_problem(text)
        if text.strip.empty?
          Issue.new(code: :blank, message: "CEP is empty")
        elsif text.length > Text::MAX_INPUT_LENGTH
          Issue.new(code: :too_long, message: "input is longer than #{Text::MAX_INPUT_LENGTH} characters")
        elsif text.match?(FORBIDDEN)
          found = Text.describe_chars(text, FORBIDDEN)
          Issue.new(code: :invalid_characters,
                    message: "only digits, dots, dashes and spaces are allowed (found #{found})")
        end
      end

      def length_issue(digits)
        Issue.new(code: :invalid_length, message: "a CEP has #{LENGTH} digits, got #{digits.length}")
      end

      def unassigned_issue
        Issue.new(code: :unassigned_prefix, message: "CEPs start at 01000-000; lower prefixes are not assigned")
      end

      # Walks +ranges+ until the +offset+-th prefix and returns it.
      def prefix_at(ranges, offset)
        ranges.each do |from, to|
          size = to - from + 1
          return from + offset if offset < size

          offset -= size
        end
      end
    end
  end
end
