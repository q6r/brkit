# frozen_string_literal: true

require_relative "result"
require_relative "rng"
require_relative "text"
require_relative "uf"

module Brkit
  # Brazilian telephone numbers (geographic numbers only).
  #
  # Rules applied, following ANATEL's numbering plan:
  #
  # * the area code (DDD) must be one of the 67 codes in {AREA_CODES};
  # * mobile numbers have 9 digits and start with 9 (+DDD 9XXXX-XXXX+);
  # * landline numbers have 8 digits and start with 2-5 (+DDD XXXX-XXXX+);
  # * eight-digit numbers starting with 6-9 are pre-"ninth digit" mobile numbers
  #   and are reported as invalid.
  #
  # Accepted notations include +"(11) 98765-4321"+, +"11987654321"+, +"+55 11 98765-4321"+,
  # +"5511987654321"+ and +"011 98765-4321"+ (national trunk prefix). The canonical
  # form is E.164 (+"+5511987654321"+). Non-Brazilian numbers and special-service
  # numbers (0800, 4004, ...) are rejected.
  module Phone
    COUNTRY_CODE = "55"

    # State => area codes (DDD), 67 in total.
    AREA_CODES_BY_UF = {
      "AC" => %w[68], "AL" => %w[82], "AM" => %w[92 97], "AP" => %w[96], "BA" => %w[71 73 74 75 77],
      "CE" => %w[85 88], "DF" => %w[61], "ES" => %w[27 28], "GO" => %w[62 64], "MA" => %w[98 99],
      "MG" => %w[31 32 33 34 35 37 38], "MS" => %w[67], "MT" => %w[65 66], "PA" => %w[91 93 94],
      "PB" => %w[83], "PE" => %w[81 87], "PI" => %w[86 89], "PR" => %w[41 42 43 44 45 46],
      "RJ" => %w[21 22 24], "RN" => %w[84], "RO" => %w[69], "RR" => %w[95], "RS" => %w[51 53 54 55],
      "SC" => %w[47 48 49], "SE" => %w[79], "SP" => %w[11 12 13 14 15 16 17 18 19], "TO" => %w[63]
    }.freeze

    # Area code => state.
    AREA_CODES = AREA_CODES_BY_UF.flat_map { |uf, codes| codes.map { |code| [code, uf] } }.sort.to_h.freeze

    FORBIDDEN = /[^0-9+().\-\s]/
    MOBILE = /\A9\d{8}\z/
    LANDLINE = /\A[2-5]\d{7}\z/
    LEGACY_MOBILE = /\A[6-9]\d{7}\z/

    class << self
      # Validates and normalises a Brazilian phone number.
      #
      # @param input [String] any of the notations listed in the module description
      # @return [Result] +normalized+ is the E.164 form; +details+ has +:area_code+, +:uf+, +:number+,
      #   +:type+ (+"mobile"+ or +"landline"+) and +:international+
      def validate(input)
        text = Text.coerce(input)
        problem = shape_problem(text)
        return failure(text, problem) if problem

        national = national_part(text)
        return failure(text, national) if national.is_a?(Issue)

        problem = national_problem(national)
        problem ? failure(text, problem) : success(text, national)
      end

      # @return [Boolean] shorthand for +validate(input).valid?+
      def valid?(input)
        validate(input).valid?
      end

      # @param input [String]
      # @return [String, nil] E.164 form (+"+5511987654321"+) of a valid number, otherwise nil
      def e164(input)
        validate(input).normalized
      end

      # @param input [String] a valid number
      # @return [String] national notation, +"(11) 98765-4321"+
      # @raise [InvalidInputError] when the number is not valid
      def format(input)
        result = validate(input)
        raise InvalidInputError, result.errors unless result.valid?

        result.formatted
      end

      # @param area_code [String]
      # @return [String, nil] the state that owns +area_code+
      def uf_for(area_code)
        AREA_CODES[area_code.to_s]
      end

      # Generates a syntactically valid number. It is synthetic and may happen to be assigned to someone.
      #
      # @param ddd [String, nil] area code; random when nil
      # @param uf [String, nil] restrict the random area code to one state (ignored when +ddd+ is given)
      # @param type [Symbol] +:mobile+ or +:landline+
      # @param formatted [Boolean] national notation instead of E.164
      # @param rng [#rand, nil] random source (see {Rng})
      # @param seed [Integer, nil] seed for a reproducible result
      # @return [String]
      # @raise [InvalidInputError] for an unknown area code, UF or type
      def generate(ddd: nil, uf: nil, type: :mobile, formatted: false, rng: nil, seed: nil)
        random = Rng.resolve(rng: rng, seed: seed)
        kind = type.to_s
        unless %w[mobile landline].include?(kind)
          raise InvalidInputError.for(:invalid_type, "type must be mobile or landline", field: "type")
        end

        area = area_code_for(ddd, uf, random)
        number = kind == "mobile" ? mobile_number(random) : landline_number(random)
        formatted ? national_notation(area, number) : "+#{COUNTRY_CODE}#{area}#{number}"
      end

      private

      def failure(text, issue)
        Result.new(kind: "phone", input: text, errors: [issue])
      end

      def success(text, national)
        area = national[0, 2]
        number = national[2..]
        type = number.length == 9 ? "mobile" : "landline"
        Result.new(
          kind: "phone", input: text, normalized: "+#{COUNTRY_CODE}#{national}",
          formatted: national_notation(area, number),
          details: { area_code: area, uf: AREA_CODES.fetch(area), number: number, type: type,
                     international: "+#{COUNTRY_CODE} #{area} #{subscriber_notation(number)}" }
        )
      end

      def shape_problem(text)
        if text.strip.empty?
          Issue.new(code: :blank, message: "phone number is empty")
        elsif text.length > Text::MAX_INPUT_LENGTH
          Issue.new(code: :too_long, message: "input is longer than #{Text::MAX_INPUT_LENGTH} characters")
        elsif text.match?(FORBIDDEN)
          found = Text.describe_chars(text, FORBIDDEN)
          Issue.new(code: :invalid_characters,
                    message: "only digits, +, parentheses, dots, dashes and spaces are allowed (found #{found})")
        end
      end

      # Strips the country code or trunk prefix. Returns the national digits or an Issue.
      def national_part(text)
        digits = text.gsub(/\D/, "")
        if text.strip.start_with?("+")
          return foreign_issue unless digits.start_with?(COUNTRY_CODE)

          digits[2..]
        elsif digits.start_with?(COUNTRY_CODE) && [12, 13].include?(digits.length)
          digits[2..]
        elsif digits.start_with?("0") && [11, 12].include?(digits.length)
          digits[1..]
        else
          digits
        end
      end

      def foreign_issue
        Issue.new(code: :foreign_number, message: "only Brazilian numbers (country code +55) are supported")
      end

      def national_problem(national)
        unless [10, 11].include?(national.length)
          return Issue.new(code: :invalid_length,
                           message: "expected 10 or 11 digits (area code + number), got #{national.length}")
        end

        area = national[0, 2]
        unless AREA_CODES.key?(area)
          return Issue.new(code: :invalid_area_code, message: "#{area} is not an area code (DDD) assigned by ANATEL")
        end

        subscriber_problem(national[2..])
      end

      def subscriber_problem(number)
        return nil if number.match?(MOBILE) || number.match?(LANDLINE)

        if number.match?(LEGACY_MOBILE)
          Issue.new(code: :legacy_mobile,
                    message: "8-digit numbers starting with 6-9 were mobile numbers before the ninth digit was added; " \
                             "mobile numbers now have 9 digits starting with 9")
        elsif number.length == 9
          Issue.new(code: :invalid_mobile, message: "9-digit (mobile) numbers must start with 9")
        else
          Issue.new(code: :invalid_landline, message: "8-digit (landline) numbers must start with 2, 3, 4 or 5")
        end
      end

      def subscriber_notation(number)
        "#{number[0...-4]}-#{number[-4..]}"
      end

      def national_notation(area, number)
        "(#{area}) #{subscriber_notation(number)}"
      end

      def area_code_for(ddd, uf, random)
        if ddd
          code = ddd.to_s
          return code if AREA_CODES.key?(code)

          raise InvalidInputError.for(:invalid_area_code, "#{code.inspect} is not an area code (DDD) assigned by ANATEL",
                                      field: "ddd")
        end
        codes = uf ? AREA_CODES_BY_UF.fetch(UF.fetch(uf)) : AREA_CODES.keys
        Rng.pick(random, codes)
      end

      def mobile_number(random)
        "9#{Rng.pick(random, [6, 7, 8, 9])}#{Rng.digits(random, 7).join}"
      end

      def landline_number(random)
        "#{Rng.pick(random, [2, 3, 4, 5])}#{Rng.digits(random, 7).join}"
      end
    end
  end
end
