# frozen_string_literal: true

require_relative "result"
require_relative "rng"
require_relative "text"

module Brkit
  # Brazilian vehicle licence plates.
  #
  # Two layouts are in use:
  #
  # * legacy: three letters and four digits, +ABC-1234+;
  # * Mercosul: three letters, a digit, a letter and two digits, +ABC1D23+.
  #
  # A legacy plate becomes its Mercosul equivalent by replacing the 5th character
  # (the second digit of the numeric part) with a letter: 0 becomes A, 1 becomes B,
  # and so on up to 9 becoming J. So +ABC-1234+ turns into +ABC1C34+.
  module Plate
    LEGACY = /\A[A-Z]{3}\d{4}\z/
    MERCOSUL = /\A[A-Z]{3}\d[A-Z]\d{2}\z/
    FORBIDDEN = /[^0-9A-Za-z\-\s]/
    # Index = digit, value = the letter that replaces it in the 5th position.
    DIGIT_LETTERS = %w[A B C D E F G H I J].freeze
    LETTERS = [*"A".."Z"].freeze

    class << self
      # Validates a plate in either layout; lower case, spaces and the legacy hyphen are accepted.
      #
      # @param input [String] e.g. +"ABC-1234"+ or +"abc1d23"+
      # @return [Result] +details[:layout]+ is +"legacy"+ or +"mercosul"+; legacy plates also
      #   report +details[:mercosul]+, their converted form
      def validate(input)
        text = Text.coerce(input)
        problem = shape_problem(text)
        return failure(text, problem) if problem

        plate = strip(text)
        if plate.match?(LEGACY)
          Result.new(kind: "plate", input: text, normalized: plate, formatted: "#{plate[0, 3]}-#{plate[3, 4]}",
                     details: { layout: "legacy", mercosul: convert_legacy(plate) })
        elsif plate.match?(MERCOSUL)
          Result.new(kind: "plate", input: text, normalized: plate, formatted: plate, details: { layout: "mercosul" })
        else
          failure(text, Issue.new(code: :invalid_format,
                                  message: "expected AAA-9999 (legacy) or AAA9A99 (Mercosul), got #{plate.inspect}"))
        end
      end

      # @return [Boolean] shorthand for +validate(input).valid?+
      def valid?(input)
        validate(input).valid?
      end

      # Converts a legacy plate to its Mercosul equivalent; a Mercosul plate is returned unchanged.
      #
      # @param input [String]
      # @return [Result] +normalized+ is the Mercosul plate. +details+ has +:from+ (layout of the input) and,
      #   for conversions, +:conversion+ with the +:position+, +:digit+ and +:letter+ involved.
      def convert(input)
        result = validate(input)
        return result unless result.valid?

        if result.details[:layout] == "mercosul"
          return Result.new(kind: "plate", input: result.input, normalized: result.normalized,
                            formatted: result.formatted, details: { from: "mercosul", layout: "mercosul" })
        end

        legacy = result.normalized
        digit = legacy[4]
        Result.new(kind: "plate", input: result.input, normalized: convert_legacy(legacy),
                   formatted: convert_legacy(legacy),
                   details: { from: "legacy", layout: "mercosul",
                              conversion: { position: 5, digit: digit, letter: DIGIT_LETTERS[digit.to_i] } })
      end

      # @param input [String] legacy or Mercosul plate
      # @return [String] the Mercosul plate
      # @raise [InvalidInputError] when +input+ is not a valid plate
      def to_mercosul(input)
        result = convert(input)
        raise InvalidInputError.new(result.errors) unless result.valid?

        result.normalized
      end

      # @param input [String]
      # @return [String] upper-case plate without hyphens or spaces
      def strip(input)
        Text.coerce(input).upcase(:ascii).gsub(/[\-\s]/, "")
      end

      # Generates a plate in the given layout. It is synthetic and may coincide with a real plate.
      #
      # @param layout [Symbol] +:mercosul+ or +:legacy+
      # @param formatted [Boolean] legacy plates get their hyphen
      # @param rng [#rand, nil] random source (see {Rng})
      # @param seed [Integer, nil] seed for a reproducible result
      # @return [String]
      # @raise [InvalidInputError] for an unknown layout
      def generate(layout: :mercosul, formatted: false, rng: nil, seed: nil)
        random = Rng.resolve(rng: rng, seed: seed)
        letters = Array.new(3) { Rng.pick(random, LETTERS) }.join
        case layout.to_s
        when "mercosul" then "#{letters}#{random.rand(10)}#{Rng.pick(random, LETTERS)}#{Rng.digits(random, 2).join}"
        when "legacy" then "#{letters}#{formatted ? '-' : ''}#{Rng.digits(random, 4).join}"
        else raise InvalidInputError.for(:invalid_layout, "layout must be mercosul or legacy", field: "layout")
        end
      end

      private

      def convert_legacy(plate)
        "#{plate[0, 4]}#{DIGIT_LETTERS[plate[4].to_i]}#{plate[5, 2]}"
      end

      def failure(text, issue)
        Result.new(kind: "plate", input: text, errors: [issue])
      end

      def shape_problem(text)
        if text.strip.empty?
          Issue.new(code: :blank, message: "plate is empty")
        elsif text.length > Text::MAX_INPUT_LENGTH
          Issue.new(code: :too_long, message: "input is longer than #{Text::MAX_INPUT_LENGTH} characters")
        elsif text.match?(FORBIDDEN)
          found = Text.describe_chars(text, FORBIDDEN)
          Issue.new(code: :invalid_characters,
                    message: "only letters, digits, hyphens and spaces are allowed (found #{found})")
        end
      end
    end
  end
end
