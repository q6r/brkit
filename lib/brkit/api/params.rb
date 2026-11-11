# frozen_string_literal: true

require_relative "../result"
require_relative "problem"

module Brkit
  module API
    # Declaration of one query parameter or JSON body field. The same declaration drives validation and the
    # OpenAPI document.
    #
    # @!attribute [r] name
    #   @return [Symbol]
    # @!attribute [r] type
    #   @return [Symbol] +:string+, +:integer+, +:boolean+ or +:decimal+ (a JSON number or a string)
    # @!attribute [r] required
    #   @return [Boolean]
    # @!attribute [r] default
    #   @return [Object, nil] applied when the value is absent
    # @!attribute [r] enum
    #   @return [Array<String>, nil] the only accepted values
    # @!attribute [r] min
    #   @return [Integer, nil]
    # @!attribute [r] max
    #   @return [Integer, nil]
    # @!attribute [r] max_length
    #   @return [Integer, nil] longest accepted string (256 when nil)
    # @!attribute [r] description
    #   @return [String, nil]
    # @!attribute [r] example
    #   @return [Object, nil]
    # @!attribute [r] fold
    #   @return [Symbol, nil] +:upcase+ or +:downcase+, applied before the +enum+ check
    Param = Struct.new(:name, :type, :required, :default, :enum, :min, :max, :max_length, :description, :example,
                       :fold, keyword_init: true) do
      def initialize(name:, type:, required: false, default: nil, enum: nil, min: nil, max: nil, max_length: nil,
                     description: nil, example: nil, fold: nil)
        super
        freeze
      end
    end

    # Declares and applies parameter specifications.
    module Params
      DEFAULT_MAX_LENGTH = 256
      BOOLEANS = { "true" => true, "1" => true, "false" => false, "0" => false }.freeze

      class << self
        # @return [Param] a string parameter
        def string(name, **options)
          Param.new(name: name, type: :string, **options)
        end

        # @return [Param] an integer parameter
        def integer(name, **options)
          Param.new(name: name, type: :integer, **options)
        end

        # @return [Param] a boolean parameter (+true+/+false+/+1+/+0+ in a query string)
        def boolean(name, **options)
          Param.new(name: name, type: :boolean, **options)
        end

        # @return [Param] a decimal amount: a JSON number or a string
        def decimal(name, **options)
          Param.new(name: name, type: :decimal, **options)
        end

        # Validates and converts query-string values.
        #
        # @param specs [Array<Param>]
        # @param raw [Hash{String=>String}] decoded query parameters
        # @return [Hash{Symbol=>Object}] converted values, defaults applied
        # @raise [Problem] 400 +invalid-parameter+ listing every problem
        def from_query(specs, raw)
          issues = unknown_issues(specs, raw.keys, :unknown_parameter, "parameter")
          values = {}
          specs.each do |spec|
            next absent(spec, values, issues) unless raw.key?(spec.name.to_s)

            value = convert_text(spec, raw[spec.name.to_s], issues)
            values[spec.name] = value unless value.nil?
          end
          raise Problem.invalid_parameter(issues) unless issues.empty?

          values
        end

        # Validates and converts the members of a parsed JSON object. +null+ counts as absent.
        #
        # @param specs [Array<Param>]
        # @param body [Hash{String=>Object}]
        # @return [Hash{Symbol=>Object}]
        # @raise [Problem] 422 +validation-error+ listing every problem
        def from_body(specs, body)
          issues = unknown_issues(specs, body.keys, :unknown_field, "field")
          values = {}
          specs.each do |spec|
            value = body[spec.name.to_s]
            next absent(spec, values, issues) if value.nil?

            converted = convert_json(spec, value, issues)
            values[spec.name] = converted unless converted.nil?
          end
          raise Problem.validation(issues) unless issues.empty?

          values
        end

        private

        def unknown_issues(specs, given, code, word)
          allowed = specs.map { |spec| spec.name.to_s }
          (given - allowed).first(10).map do |name|
            Issue.new(code: code, field: name[0, 40],
                      message: "unknown #{word} #{name[0, 40].inspect}; allowed: #{allowed.join(', ')}")
          end
        end

        def absent(spec, values, issues)
          if spec.required
            issues << Issue.new(code: :missing, field: spec.name.to_s, message: "#{spec.name} is required")
          elsif !spec.default.nil?
            values[spec.name] = spec.default
          end
        end

        def convert_text(spec, text, issues)
          case spec.type
          when :string then check_string(spec, fold(spec, text), issues)
          when :integer then convert_integer(spec, text, issues)
          else convert_boolean(spec, text, issues)
          end
        end

        def convert_integer(spec, text, issues)
          return problem(spec, :invalid_integer, "#{spec.name} must be an integer", issues) unless
            text.match?(/\A-?\d{1,10}\z/)

          check_number(spec, text.to_i, issues)
        end

        def convert_boolean(spec, text, issues)
          BOOLEANS.fetch(text.downcase) do
            problem(spec, :invalid_boolean, "#{spec.name} must be true or false", issues)
          end
        end

        def convert_json(spec, value, issues)
          case spec.type
          when :string then json_string(spec, value, issues)
          when :integer then json_integer(spec, value, issues)
          when :boolean then json_boolean(spec, value, issues)
          else json_decimal(spec, value, issues)
          end
        end

        def json_string(spec, value, issues)
          return problem(spec, :invalid_type, "#{spec.name} must be a string", issues) unless value.is_a?(String)

          check_string(spec, fold(spec, value), issues)
        end

        def json_integer(spec, value, issues)
          return problem(spec, :invalid_type, "#{spec.name} must be an integer", issues) unless value.is_a?(Integer)

          check_number(spec, value, issues)
        end

        def json_boolean(spec, value, issues)
          return value if [true, false].include?(value)

          problem(spec, :invalid_type, "#{spec.name} must be true or false", issues)
        end

        def json_decimal(spec, value, issues)
          return check_string(spec, value, issues) if value.is_a?(String)
          return value if value.is_a?(Integer) || (value.is_a?(Float) && value.finite?)

          problem(spec, :invalid_type, "#{spec.name} must be a number or a string", issues)
        end

        def fold(spec, text)
          case spec.fold
          when :upcase then text.upcase
          when :downcase then text.downcase
          else text
          end
        end

        def check_string(spec, value, issues)
          limit = spec.max_length || DEFAULT_MAX_LENGTH
          if value.length > limit
            return problem(spec, :too_long, "#{spec.name} can have at most #{limit} characters", issues)
          end
          return value unless spec.enum && !spec.enum.include?(value)

          problem(spec, :not_allowed, "#{spec.name} must be one of: #{spec.enum.join(', ')}", issues)
        end

        def check_number(spec, value, issues)
          return value if (spec.min.nil? || value >= spec.min) && (spec.max.nil? || value <= spec.max)

          problem(spec, :out_of_range, "#{spec.name} must be between #{spec.min} and #{spec.max}", issues)
        end

        # Records an issue and returns nil so callers can use it as their result.
        def problem(spec, code, message, issues)
          issues << Issue.new(code: code, message: message, field: spec.name.to_s)
          nil
        end
      end
    end
  end
end
