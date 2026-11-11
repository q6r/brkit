# frozen_string_literal: true

module Brkit
  # The Luhn (mod 10) checksum used by payment card numbers.
  module Luhn
    class << self
      # @param digits [String] decimal digits only
      # @return [Boolean] true when the number passes the Luhn check
      def valid?(digits)
        digits.match?(/\A\d{2,}\z/) && (weighted_sum(digits, 0) % 10).zero?
      end

      # Appends the check digit that makes +payload+ pass {.valid?}.
      #
      # @param payload [String] digits without check digit
      # @return [String] payload plus one digit
      def complete(payload)
        "#{payload}#{check_digit(payload)}"
      end

      # @param payload [String] digits without check digit
      # @return [Integer] the digit that makes +payload+ + digit pass the check
      def check_digit(payload)
        (10 - (weighted_sum(payload, 1) % 10)) % 10
      end

      # Position-by-position walk-through of the check, as plain data for UIs.
      #
      # @param digits [String] decimal digits only
      # @return [Hash{Symbol=>Object}] +entries+ (right to left: digit, doubled, contribution), +sum+, +remainder+
      def steps(digits)
        entries = digits.reverse.each_char.with_index.map do |char, index|
          value = char.to_i
          doubled = index.odd?
          { digit: value, doubled: doubled, contribution: doubled ? double(value) : value }
        end
        sum = entries.sum { |entry| entry[:contribution] }
        { entries: entries, sum: sum, remainder: sum % 10 }
      end

      private

      # Sums the digits from the right, doubling every second one. +offset+ shifts
      # the position counter: 0 for a complete number (check digit at index 0),
      # 1 for a payload that still lacks its check digit.
      def weighted_sum(digits, offset)
        digits.reverse.each_char.with_index.sum do |char, index|
          value = char.to_i
          (index + offset).odd? ? double(value) : value
        end
      end

      def double(value)
        doubled = value * 2
        doubled > 9 ? doubled - 9 : doubled
      end
    end
  end
end
