# frozen_string_literal: true

require_relative "../cnpj"
require_relative "../cpf"
require_relative "../phone"
require_relative "../result"
require_relative "../text"

module Brkit
  module Pix
    # Parses and normalises PIX keys (chaves) into the form written inside a BR Code.
    #
    # Five kinds exist; the encoding follows the Banco Central "Manual de Padrões para Iniciação do Pix":
    #
    # * +cpf+: 11 digits, no punctuation;
    # * +cnpj+: 14 characters, no punctuation (letters allowed since the alphanumeric CNPJ);
    # * +phone+: international format +"+5561912345678"+ (mobile numbers only);
    # * +email+: as registered, written here in lower case (at most 77 characters);
    # * +evp+: the random key, a UUID with hyphens.
    module Key
      TYPES = %w[cpf cnpj phone email evp].freeze
      MAX_LENGTH = 77
      MAX_INPUT_LENGTH = 100

      EVP = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/
      CPF_SHAPE = /\A\d{3}\.?\d{3}\.?\d{3}-?\d{2}\z/
      CNPJ_SHAPE = %r{\A[0-9A-Za-z]{2}\.?[0-9A-Za-z]{3}\.?[0-9A-Za-z]{3}/?[0-9A-Za-z]{4}-?\d{2}\z}
      LABEL = "[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?"
      EMAIL = /\A[A-Za-z0-9.!#$%&'*+\/=?^_`{|}~-]{1,64}@#{LABEL}(?:\.#{LABEL})+\z/

      UNRECOGNISED = "could not tell the key type: use a CPF, a CNPJ, a mobile number in +55 format, " \
                     "an e-mail address or a random key (UUID)"
      private_constant :UNRECOGNISED

      class << self
        # @param raw [String] the key as typed by a person
        # @param type [String, Symbol, nil] force one of {TYPES}; detected from the shape when nil
        # @return [Result] +normalized+ is the value to put in the payload; +details[:type]+ is the key type
        def parse(raw, type: nil)
          text = Text.coerce(raw).strip
          return failure(text, :blank, "key is empty") if text.empty?
          return failure(text, :too_long, "key is longer than #{MAX_INPUT_LENGTH} characters") if too_long?(text)

          kind = type.nil? ? detect(text) : type.to_s.downcase
          return failure(text, :unrecognised_key, UNRECOGNISED) if kind.nil?

          dispatch(text, kind)
        end

        # @return [String, nil] the key type suggested by the shape of +text+ (not a validity check)
        def detect(text)
          return "phone" if text.start_with?("+")
          return "email" if text.include?("@")
          return "evp" if text.match?(EVP)
          return "cpf" if text.match?(CPF_SHAPE)
          return "cnpj" if text.match?(CNPJ_SHAPE)

          "phone" if text.match?(/[()\s]/) && Phone.valid?(text)
        end

        private

        def too_long?(text)
          text.length > MAX_INPUT_LENGTH
        end

        def dispatch(text, kind)
          case kind
          when "cpf" then parse_cpf(text)
          when "cnpj" then from_document(text, CNPJ.validate(text), "cnpj")
          when "phone" then parse_phone(text)
          when "email" then parse_email(text)
          when "evp" then parse_evp(text)
          else failure(text, :invalid_key_type, "key type must be one of #{TYPES.join(', ')}")
          end
        end

        def parse_cpf(text)
          inner = CPF.validate(text)
          hint = !inner.valid? && Phone.valid?(text) ? phone_hint(text) : ""
          from_document(text, inner, "cpf", hint: hint)
        end

        def phone_hint(text)
          "; phone keys must be written in international format, for example #{Phone.e164(text)}"
        end

        # Wraps the result of CPF/CNPJ/Phone validation as a key result.
        def from_document(text, inner, type, hint: "")
          errors = inner.errors.map { |issue| Issue.new(code: issue.code, message: "#{issue.message}#{hint}") }
          Result.new(kind: "pix_key", input: text, normalized: inner.valid? ? inner.normalized : nil,
                     formatted: inner.valid? ? inner.formatted : nil, errors: errors, details: { type: type })
        end

        def parse_phone(text)
          inner = Phone.validate(text)
          if inner.valid? && inner.details[:type] != "mobile"
            return failure(text, :not_mobile, "a PIX phone key must be a mobile number", type: "phone")
          end

          from_document(text, inner, "phone")
        end

        def parse_email(text)
          key = text.downcase
          return failure(text, :invalid_email, "not a valid e-mail address", type: "email") unless key.match?(EMAIL)

          if key.length > MAX_LENGTH
            return failure(text, :too_long, "an e-mail key has at most #{MAX_LENGTH} characters", type: "email")
          end

          Result.new(kind: "pix_key", input: text, normalized: key, formatted: key, details: { type: "email" })
        end

        def parse_evp(text)
          unless text.match?(EVP)
            return failure(text, :invalid_evp, "a random key looks like 123e4567-e12b-12d1-a456-426655440000",
                           type: "evp")
          end

          Result.new(kind: "pix_key", input: text, normalized: text.downcase, formatted: text.downcase,
                     details: { type: "evp" })
        end

        def failure(text, code, message, type: nil)
          Result.new(kind: "pix_key", input: text, errors: [Issue.new(code: code, message: message)],
                     details: type ? { type: type } : {})
        end
      end
    end
  end
end
