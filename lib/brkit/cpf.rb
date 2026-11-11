# frozen_string_literal: true

require_relative "mod11"
require_relative "result"
require_relative "rng"
require_relative "text"
require_relative "uf"

module Brkit
  # CPF (Cadastro de Pessoas Físicas), the 11-digit Brazilian individual taxpayer number.
  #
  # Layout: 8 serial digits, 1 fiscal-region digit and 2 check digits, written
  # +NNN.NNN.NNN-DD+. Both check digits use the weighted mod-11 scheme of
  # {Mod11} (weights 10..2, then 11..2).
  #
  #   Brkit::CPF.valid?("529.982.247-25")    #=> true
  #   Brkit::CPF.generate(uf: "SP", seed: 7) #=> a reproducible, checksum-valid CPF
  module CPF
    LENGTH = 11
    BASE_LENGTH = 9
    FIRST_WEIGHTS = [10, 9, 8, 7, 6, 5, 4, 3, 2].freeze
    SECOND_WEIGHTS = [11, 10, 9, 8, 7, 6, 5, 4, 3, 2].freeze
    FORBIDDEN = /[^0-9.\-\s]/

    # Fiscal region (9th digit) => states whose CPFs were registered there.
    REGIONS = {
      0 => %w[RS],
      1 => %w[DF GO MS MT TO],
      2 => %w[AC AM AP PA RO RR],
      3 => %w[CE MA PI],
      4 => %w[AL PB PE RN],
      5 => %w[BA SE],
      6 => %w[MG],
      7 => %w[ES RJ],
      8 => %w[SP],
      9 => %w[PR SC]
    }.freeze

    class << self
      # Validates a CPF written with or without punctuation.
      #
      # @param input [String] e.g. +"529.982.247-25"+ or +"52998224725"+
      # @param explain [Boolean] add the step-by-step checksum computation to +details[:steps]+
      # @return [Result] +details+ has +:region_digit+ and +:ufs+ for 11-digit inputs
      def validate(input, explain: false)
        text = Text.coerce(input)
        problem = shape_problem(text)
        return result(text, nil, [problem]) if problem

        digits = strip(text)
        return result(text, digits, [length_issue(digits)]) unless digits.length == LENGTH
        return result(text, digits, [repeated_issue], region_details(digits)) if digits.squeeze.length == 1

        checked = check(digits)
        details = region_details(digits)
        details[:steps] = checked[:steps] if explain
        result(text, digits, checked[:errors], details)
      end

      # @return [Boolean] shorthand for +validate(input).valid?+
      def valid?(input)
        validate(input).valid?
      end

      # @param input [String]
      # @return [String] the digits of +input+ with all punctuation removed
      def strip(input)
        Text.coerce(input).gsub(/\D/, "")
      end

      # Applies the +NNN.NNN.NNN-DD+ mask.
      #
      # @param input [String] exactly 11 digits once punctuation is removed
      # @return [String]
      # @raise [InvalidInputError] when +input+ does not hold 11 digits
      def format(input)
        digits = strip(input)
        raise InvalidInputError, [length_issue(digits)] unless digits.length == LENGTH

        mask(digits)
      end

      # Generates a CPF that passes {.validate}. It is synthetic: not a real person's number.
      #
      # @param uf [String, nil] state whose fiscal-region digit the number should carry
      # @param formatted [Boolean] apply the mask
      # @param rng [#rand, nil] random source (see {Rng})
      # @param seed [Integer, nil] seed for a reproducible result
      # @return [String]
      # @raise [InvalidInputError] for an unknown +uf+
      def generate(uf: nil, formatted: false, rng: nil, seed: nil)
        random = Rng.resolve(rng: rng, seed: seed)
        region = uf.nil? ? nil : region_for(UF.fetch(uf))
        base = random_base(random, region)
        digits = (base + check_digits(base)).join
        formatted ? mask(digits) : digits
      end

      # The fiscal region of a CPF.
      #
      # @param input [String]
      # @return [Hash{Symbol=>Object}, nil] +{ digit:, ufs: }+, or nil unless the input has 11 digits
      def region(input)
        digits = strip(input)
        return nil unless digits.length == LENGTH

        info = region_details(digits)
        { digit: info[:region_digit], ufs: info[:ufs] }
      end

      # Computes the two check digits for nine base digits.
      #
      # @param base [Array<Integer>] nine digits
      # @return [Array<Integer>] the two check digits
      def check_digits(base)
        first = Mod11.step(values: base, weights: FIRST_WEIGHTS)[:check_digit]
        second = Mod11.step(values: base + [first], weights: SECOND_WEIGHTS)[:check_digit]
        [first, second]
      end

      private

      def mask(digits)
        "#{digits[0, 3]}.#{digits[3, 3]}.#{digits[6, 3]}-#{digits[9, 2]}"
      end

      def result(text, digits, errors, details = {})
        full = digits&.length == LENGTH
        Result.new(kind: "cpf", input: text, normalized: full ? digits : nil,
                   formatted: full ? mask(digits) : nil, errors: errors, details: details)
      end

      def shape_problem(text)
        if text.strip.empty?
          Issue.new(code: :blank, message: "CPF is empty")
        elsif text.length > Text::MAX_INPUT_LENGTH
          Issue.new(code: :too_long, message: "input is longer than #{Text::MAX_INPUT_LENGTH} characters")
        elsif text.match?(FORBIDDEN)
          found = Text.describe_chars(text, FORBIDDEN)
          Issue.new(code: :invalid_characters,
                    message: "only digits, dots, dashes and spaces are allowed (found #{found})")
        end
      end

      def length_issue(digits)
        Issue.new(code: :invalid_length, message: "a CPF has #{LENGTH} digits, got #{digits.length}")
      end

      def repeated_issue
        Issue.new(code: :repeated_digits, message: "all digits are the same, which is never a valid CPF")
      end

      def check(digits)
        numbers = digits.each_char.map(&:to_i)
        base = numbers.first(BASE_LENGTH)
        first = Mod11.step(values: base, weights: FIRST_WEIGHTS, label: "first check digit")
        first = Mod11.compare(first, numbers[9])
        second = Mod11.step(values: base + [first[:check_digit]], weights: SECOND_WEIGHTS, label: "second check digit")
        second = Mod11.compare(second, numbers[10])
        errors = [first, second].reject { |step| step[:match] }.map { |step| checksum_issue(step) }
        { steps: [first, second], errors: errors }
      end

      def checksum_issue(step)
        Issue.new(code: :checksum,
                  message: "#{step[:label]} does not match (expected #{step[:check_digit]}, got #{step[:actual]})")
      end

      def region_details(digits)
        digit = digits[8].to_i
        { region_digit: digit, ufs: REGIONS.fetch(digit) }
      end

      def region_for(uf)
        REGIONS.find { |_digit, ufs| ufs.include?(uf) }.first
      end

      # Nine random digits (never all the same), the ninth forced to +region+ when given.
      def random_base(random, region)
        Rng.attempt("a CPF") do
          base = Rng.digits(random, BASE_LENGTH)
          base[8] = region if region
          base unless base.uniq.length == 1
        end
      end
    end
  end
end
