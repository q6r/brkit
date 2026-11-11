# frozen_string_literal: true

require "json"

module Brkit
  # One problem found while validating or building a value.
  #
  # @!attribute [r] code
  #   @return [Symbol] stable, machine-readable identifier such as +:checksum+
  # @!attribute [r] message
  #   @return [String] human-readable explanation (English)
  # @!attribute [r] field
  #   @return [String, nil] name of the input field the problem refers to (builders only)
  Issue = Struct.new(:code, :message, :field, keyword_init: true) do
    def initialize(code:, message:, field: nil)
      super
      freeze
    end

    # @return [Hash{Symbol=>String}] JSON-friendly form; +field+ is omitted when nil
    def to_h
      { code: code.to_s, message: message, field: field }.compact
    end
  end

  # Immutable outcome of validating one value (CPF, CNPJ, PIX payload, ...).
  #
  # Every validator in the library returns a Result, so callers handle all
  # documents the same way:
  #
  #   result = Brkit::CPF.validate("529.982.247-25")
  #   result.valid?      #=> true
  #   result.normalized  #=> "52998224725"
  #   result.formatted   #=> "529.982.247-25"
  #   result.errors      #=> []
  #   result.details     #=> { region_digit: 7, ufs: ["ES", "RJ"] }
  #
  # @!attribute [r] kind
  #   @return [String] document type, for example +"cpf"+
  # @!attribute [r] input
  #   @return [String] the value as received (coerced to a UTF-8 string)
  # @!attribute [r] normalized
  #   @return [String, nil] canonical form; present whenever the input has the right shape,
  #     even when a checksum fails, so callers can echo it back
  # @!attribute [r] formatted
  #   @return [String, nil] display form (masked) when the shape allows it
  # @!attribute [r] errors
  #   @return [Array<Issue>] empty when the value is valid
  # @!attribute [r] details
  #   @return [Hash{Symbol=>Object}] document specific facts (region, brand, checksum steps, ...)
  Result = Struct.new(:kind, :input, :normalized, :formatted, :errors, :details, keyword_init: true) do
    def initialize(kind:, input:, normalized: nil, formatted: nil, errors: [], details: {})
      super(
        kind: kind.to_s,
        input: Result.deep_freeze(input),
        normalized: Result.deep_freeze(normalized),
        formatted: Result.deep_freeze(formatted),
        errors: errors.dup.freeze,
        details: Result.deep_freeze(details)
      )
      freeze
    end

    # Recursively freezes +value+ without touching objects owned by the caller.
    # @api private
    def self.deep_freeze(value)
      case value
      when Hash then value.each_with_object({}) { |(key, item), copy| copy[key] = deep_freeze(item) }.freeze
      when Array then value.map { |item| deep_freeze(item) }.freeze
      when String then value.frozen? ? value : value.dup.freeze
      else value
      end
    end

    # @return [Boolean] true when no error was found
    def valid?
      errors.empty?
    end

    # @return [Array<String>] the error messages, in order
    def error_messages
      errors.map(&:message)
    end

    # @return [Hash{Symbol=>Object}] JSON-friendly representation (symbol keys)
    def to_h
      {
        kind: kind,
        input: input,
        valid: valid?,
        normalized: normalized,
        formatted: formatted,
        errors: errors.map(&:to_h),
        details: details
      }
    end

    # Serialises through {#to_h}; works with +JSON.generate(result)+.
    def to_json(*args)
      to_h.to_json(*args)
    end
  end
end
