# frozen_string_literal: true

require_relative "mod11"
require_relative "result"
require_relative "rng"
require_relative "text"

module Brkit
  # PIS / PASEP / NIS / NIT, the 11-digit Brazilian social-registration number.
  #
  # The four names share one format: 10 digits plus a check digit computed with
  # the weighted mod-11 scheme of {Mod11} (weights 3, 2, 9, 8, 7, 6, 5, 4, 3, 2).
  # Written +NNN.NNNNN.NN-D+.
  #
  #   Brkit::PIS.valid?("123.45678.91-9") #=> true
  module PIS
    LENGTH = 11
    WEIGHTS = [3, 2, 9, 8, 7, 6, 5, 4, 3, 2].freeze
    FORBIDDEN = /[^0-9.\-\s]/

    class << self
      # Validates a PIS/PASEP/NIS/NIT number written with or without punctuation.
      #
      # @param input [String] e.g. +"123.45678.91-9"+ or +"12345678919"+
      # @param explain [Boolean] add the step-by-step checksum computation to +details[:steps]+
      # @return [Result]
      def validate(input, explain: false)
        text = Text.coerce(input)
        problem = shape_problem(text)
        return result(text, nil, [problem]) if problem

        digits = strip(text)
        return result(text, digits, [length_issue(digits)]) unless digits.length == LENGTH
        return result(text, digits, [repeated_issue]) if digits.squeeze.length == 1

        step = Mod11.compare(Mod11.step(values: numbers(digits).first(10), weights: WEIGHTS, label: "check digit"),
                             digits[10].to_i)
        details = explain ? { steps: [step] } : {}
        result(text, digits, step[:match] ? [] : [checksum_issue(step)], details)
      end

      # @return [Boolean] shorthand for +validate(input).valid?+
      def valid?(input)
        validate(input).valid?
      end

      # @return [String] the digits of +input+ with all punctuation removed
      def strip(input)
        Text.coerce(input).gsub(/\D/, "")
      end

      # Applies the +NNN.NNNNN.NN-D+ mask.
      #
      # @param input [String] exactly 11 digits once punctuation is removed
      # @return [String]
      # @raise [InvalidInputError] when +input+ does not hold 11 digits
      def format(input)
        digits = strip(input)
        raise InvalidInputError, [length_issue(digits)] unless digits.length == LENGTH

        mask(digits)
      end

      # Computes the check digit for ten base digits.
      #
      # @param base [Array<Integer>] ten digits
      # @return [Integer]
      def check_digit(base)
        Mod11.step(values: base, weights: WEIGHTS)[:check_digit]
      end

      # Generates a number that passes {.validate}. It is synthetic, not a real registration.
      #
      # @param formatted [Boolean] apply the mask
      # @param rng [#rand, nil] random source (see {Rng})
      # @param seed [Integer, nil] seed for a reproducible result
      # @return [String]
      def generate(formatted: false, rng: nil, seed: nil)
        random = Rng.resolve(rng: rng, seed: seed)
        digits = Rng.attempt("a PIS") do
          base = Rng.digits(random, 10)
          candidate = (base + [check_digit(base)]).join
          candidate unless candidate.squeeze.length == 1
        end
        formatted ? mask(digits) : digits
      end

      private

      def numbers(digits)
        digits.each_char.map(&:to_i)
      end

      def mask(digits)
        "#{digits[0, 3]}.#{digits[3, 5]}.#{digits[8, 2]}-#{digits[10, 1]}"
      end

      def result(text, digits, errors, details = {})
        full = digits&.length == LENGTH
        Result.new(kind: "pis", input: text, normalized: full ? digits : nil,
                   formatted: full ? mask(digits) : nil, errors: errors, details: details)
      end

      def shape_problem(text)
        if text.strip.empty?
          Issue.new(code: :blank, message: "PIS is empty")
        elsif text.length > Text::MAX_INPUT_LENGTH
          Issue.new(code: :too_long, message: "input is longer than #{Text::MAX_INPUT_LENGTH} characters")
        elsif text.match?(FORBIDDEN)
          found = Text.describe_chars(text, FORBIDDEN)
          Issue.new(code: :invalid_characters,
                    message: "only digits, dots, dashes and spaces are allowed (found #{found})")
        end
      end

      def length_issue(digits)
        Issue.new(code: :invalid_length, message: "a PIS has #{LENGTH} digits, got #{digits.length}")
      end

      def repeated_issue
        Issue.new(code: :repeated_digits, message: "all digits are the same, which is never a valid PIS")
      end

      def checksum_issue(step)
        Issue.new(code: :checksum,
                  message: "check digit does not match (expected #{step[:check_digit]}, got #{step[:actual]})")
      end
    end
  end
end
