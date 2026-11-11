# frozen_string_literal: true

module Brkit
  # The weighted modulo-11 check-digit scheme used by CPF, CNPJ and PIS.
  #
  # Each step multiplies the digits by a weight list, adds the products and
  # takes the remainder modulo 11. A remainder below 2 yields check digit 0,
  # otherwise the digit is +11 - remainder+.
  #
  # Steps are plain data so UIs can replay the computation ("show your work").
  # @api private
  module Mod11
    MODULUS = 11

    class << self
      # @param values [Array<Integer>] numeric value of each position
      # @param weights [Array<Integer>] same length as +values+
      # @param chars [Array<String>, nil] original characters (differs from values for alphanumeric CNPJ)
      # @param label [String, nil] short description, e.g. "first check digit"
      # @return [Hash{Symbol=>Object}] label, chars, values, weights, products, sum, modulus, remainder, check_digit
      def step(values:, weights:, chars: nil, label: nil)
        products = values.zip(weights).map { |value, weight| value * weight }
        sum = products.sum
        remainder = sum % MODULUS
        {
          label: label,
          chars: chars || values.map(&:to_s),
          values: values,
          weights: weights,
          products: products,
          sum: sum,
          modulus: MODULUS,
          remainder: remainder,
          check_digit: digit_for(remainder)
        }
      end

      # @param remainder [Integer] sum modulo 11
      # @return [Integer] the check digit
      def digit_for(remainder)
        remainder < 2 ? 0 : MODULUS - remainder
      end

      # Adds the +actual+ digit found in the input and whether it matches.
      #
      # @param step [Hash] result of {.step}
      # @param actual [Integer] check digit present in the input
      # @return [Hash]
      def compare(step, actual)
        step.merge(actual: actual, match: step[:check_digit] == actual)
      end
    end
  end
end
