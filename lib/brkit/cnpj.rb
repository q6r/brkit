# frozen_string_literal: true

require_relative "mod11"
require_relative "result"
require_relative "rng"
require_relative "text"

module Brkit
  # CNPJ (Cadastro Nacional da Pessoa Jurídica), the 14-character Brazilian company number.
  #
  # Layout: 8 root characters, 4 branch ("ordem") characters and 2 check digits,
  # written +CC.CCC.CCC/CCCC-DD+ (C is a character, D a digit). The classic CNPJ is numeric. Since July 2026 the
  # first 12 characters may also be the letters A-Z (the "alphanumeric CNPJ"):
  # each character counts as +ord(char) - 48+ (so +"A"+ is 17), the weights and the
  # mod-11 rule are unchanged and the two check digits are always numeric.
  #
  #   Brkit::CNPJ.valid?("11.222.333/0001-81")   #=> true (classic)
  #   Brkit::CNPJ.valid?("12.ABC.345/01DE-35")   #=> true (alphanumeric)
  #   Brkit::CNPJ.check_digits("12ABC34501DE")   #=> "35"
  module CNPJ
    LENGTH = 14
    BASE_LENGTH = 12
    ROOT_LENGTH = 8
    BRANCH_LENGTH = 4
    FIRST_WEIGHTS = [5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2].freeze
    SECOND_WEIGHTS = [6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2].freeze
    DIGITS = %w[0 1 2 3 4 5 6 7 8 9].freeze
    LETTERS = [*"A".."Z"].freeze
    ALPHABET = (DIGITS + LETTERS).freeze
    # Value of a character is its ASCII code minus this offset ("0" => 0, "A" => 17).
    ASCII_OFFSET = 48
    SEPARATORS = %r{[./\-\s]}
    FORBIDDEN = %r{[^0-9A-Za-z./\-\s]}

    class << self
      # Validates a classic or alphanumeric CNPJ written with or without punctuation.
      # Lower-case letters are accepted and normalised to upper case.
      #
      # @param input [String] e.g. +"11.222.333/0001-81"+ or +"12ABC34501DE35"+
      # @param explain [Boolean] add the step-by-step checksum computation to +details[:steps]+
      # @return [Result] +details+ has +:root+, +:branch+, +:check_digits+, +:alphanumeric+, +:headquarters+
      def validate(input, explain: false)
        text = Text.coerce(input)
        problem = shape_problem(text)
        return result(text, nil, [problem]) if problem

        chars = strip(text)
        return result(text, chars, [length_issue(chars)]) unless chars.length == LENGTH
        return result(text, chars, [digits_issue]) unless chars.match?(/\A[0-9A-Z]{12}\d{2}\z/)

        details = identity_details(chars)
        return result(text, chars, [repeated_issue], details) if chars.squeeze.length == 1

        checked = check(chars)
        details[:steps] = checked[:steps] if explain
        result(text, chars, checked[:errors], details)
      end

      # @return [Boolean] shorthand for +validate(input).valid?+
      def valid?(input)
        validate(input).valid?
      end

      # Removes punctuation and upper-cases the rest.
      #
      # @param input [String]
      # @return [String]
      def strip(input)
        Text.coerce(input).upcase(:ascii).gsub(SEPARATORS, "")
      end

      # Applies the +CC.CCC.CCC/CCCC-DD+ mask.
      #
      # @param input [String] 14 characters once punctuation is removed
      # @return [String]
      # @raise [InvalidInputError] when +input+ does not hold 14 characters
      def format(input)
        chars = strip(input)
        raise InvalidInputError, [length_issue(chars)] unless chars.length == LENGTH

        mask(chars)
      end

      # Computes the two check digits for the first twelve characters.
      #
      # @param base [String] 12 characters from +0-9A-Z+ (root + branch)
      # @return [String] two digits, e.g. +"35"+ for +"12ABC34501DE"+
      # @raise [InvalidInputError] when +base+ is not 12 characters from +0-9A-Z+
      def check_digits(base)
        text = base.to_s.upcase(:ascii)
        unless text.match?(/\A[0-9A-Z]{12}\z/)
          raise InvalidInputError.for(:invalid_base, "the base must be 12 characters from 0-9 and A-Z")
        end

        first = Mod11.step(values: values_of(text), weights: FIRST_WEIGHTS)[:check_digit]
        second = Mod11.step(values: values_of("#{text}#{first}"), weights: SECOND_WEIGHTS)[:check_digit]
        "#{first}#{second}"
      end

      # Generates a CNPJ that passes {.validate}. It is synthetic: not a real company's number.
      #
      # @param alphanumeric [Boolean] when true the root holds at least one letter
      # @param formatted [Boolean] apply the mask
      # @param branch [String] four characters; the default +"0001"+ is the head office
      # @param rng [#rand, nil] random source (see {Rng})
      # @param seed [Integer, nil] seed for a reproducible result
      # @return [String]
      # @raise [InvalidInputError] when +branch+ is malformed (or has letters while +alphanumeric+ is false)
      def generate(alphanumeric: false, formatted: false, branch: "0001", rng: nil, seed: nil)
        random = Rng.resolve(rng: rng, seed: seed)
        suffix = branch_for(branch, alphanumeric)
        cnpj = Rng.attempt("a CNPJ") do
          base = random_root(random, alphanumeric) + suffix
          candidate = base + check_digits(base)
          candidate unless candidate.squeeze.length == 1
        end
        formatted ? mask(cnpj) : cnpj
      end

      private

      def values_of(chars)
        chars.each_char.map { |char| char.ord - ASCII_OFFSET }
      end

      def mask(chars)
        "#{chars[0, 2]}.#{chars[2, 3]}.#{chars[5, 3]}/#{chars[8, 4]}-#{chars[12, 2]}"
      end

      def result(text, chars, errors, details = {})
        full = chars&.length == LENGTH
        Result.new(kind: "cnpj", input: text, normalized: full ? chars : nil,
                   formatted: full ? mask(chars) : nil, errors: errors, details: details)
      end

      def shape_problem(text)
        if text.strip.empty?
          Issue.new(code: :blank, message: "CNPJ is empty")
        elsif text.length > Text::MAX_INPUT_LENGTH
          Issue.new(code: :too_long, message: "input is longer than #{Text::MAX_INPUT_LENGTH} characters")
        elsif text.match?(FORBIDDEN)
          found = Text.describe_chars(text, FORBIDDEN)
          Issue.new(code: :invalid_characters,
                    message: "only letters A-Z, digits, dots, slashes, dashes and spaces are allowed (found #{found})")
        end
      end

      def length_issue(chars)
        Issue.new(code: :invalid_length, message: "a CNPJ has #{LENGTH} characters, got #{chars.length}")
      end

      def digits_issue
        Issue.new(code: :invalid_check_digits, message: "the last two characters (check digits) must be digits")
      end

      def repeated_issue
        Issue.new(code: :repeated_digits, message: "all characters are the same, which is never a valid CNPJ")
      end

      def identity_details(chars)
        {
          root: chars[0, ROOT_LENGTH],
          branch: chars[ROOT_LENGTH, BRANCH_LENGTH],
          check_digits: chars[BASE_LENGTH, 2],
          alphanumeric: !chars[0, BASE_LENGTH].match?(/\A\d+\z/),
          headquarters: chars[ROOT_LENGTH, BRANCH_LENGTH] == "0001"
        }
      end

      def check(chars)
        base = chars[0, BASE_LENGTH]
        first = Mod11.step(values: values_of(base), weights: FIRST_WEIGHTS, chars: base.chars,
                           label: "first check digit")
        first = Mod11.compare(first, chars[12].to_i)
        second_chars = "#{base}#{first[:check_digit]}"
        second = Mod11.step(values: values_of(second_chars), weights: SECOND_WEIGHTS, chars: second_chars.chars,
                            label: "second check digit")
        second = Mod11.compare(second, chars[13].to_i)
        errors = [first, second].reject { |step| step[:match] }.map { |step| checksum_issue(step) }
        { steps: [first, second], errors: errors }
      end

      def checksum_issue(step)
        Issue.new(code: :checksum,
                  message: "#{step[:label]} does not match (expected #{step[:check_digit]}, got #{step[:actual]})")
      end

      def branch_for(branch, alphanumeric)
        text = branch.to_s.upcase(:ascii)
        pattern = alphanumeric ? /\A[0-9A-Z]{4}\z/ : /\A\d{4}\z/
        return text if text.match?(pattern)

        allowed = alphanumeric ? "4 characters from 0-9 and A-Z" : "4 digits (use alphanumeric: true for letters)"
        raise InvalidInputError.for(:invalid_branch, "branch must be #{allowed}", field: "branch")
      end

      # Eight random root characters; in alphanumeric mode at least one of them is a letter.
      def random_root(random, alphanumeric)
        alphabet = alphanumeric ? ALPHABET : DIGITS
        root = Array.new(ROOT_LENGTH) { Rng.pick(random, alphabet) }
        root[random.rand(ROOT_LENGTH)] = Rng.pick(random, LETTERS) if alphanumeric && root.none? { |char| LETTERS.include?(char) }
        root.join
      end
    end
  end
end
