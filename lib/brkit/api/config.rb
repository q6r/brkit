# frozen_string_literal: true

require_relative "../errors"

module Brkit
  module API
    # Raised when an environment variable holds an unusable value.
    class ConfigError < Brkit::Error; end

    # Runtime settings of the HTTP API, normally read from environment variables.
    #
    # | Variable | Meaning | Default |
    # |---|---|---|
    # | +BRKIT_CORS_ORIGIN+ | comma-separated origins allowed to call the API from a browser, or +*+ | none (CORS off) |
    # | +BRKIT_MAX_BODY_BYTES+ | largest accepted request body | 16384 |
    # | +BRKIT_RATE_LIMIT+ | sustained requests per minute per client; 0 turns limiting off | 120 |
    # | +BRKIT_RATE_BURST+ | token-bucket size (requests allowed in a burst) | 40 |
    # | +BRKIT_TRUST_PROXY+ | +1+ to take the client address from +X-Forwarded-For+ | off |
    #
    # @!attribute [r] cors_origins
    #   @return [Array<String>] allowed origins, or +["*"]+
    # @!attribute [r] max_body_bytes
    #   @return [Integer]
    # @!attribute [r] rate_limit_per_minute
    #   @return [Integer] 0 disables the limiter
    # @!attribute [r] rate_burst
    #   @return [Integer]
    # @!attribute [r] trust_proxy
    #   @return [Boolean]
    Config = Struct.new(:cors_origins, :max_body_bytes, :rate_limit_per_minute, :rate_burst, :trust_proxy,
                        keyword_init: true) do
      def initialize(cors_origins: [], max_body_bytes: 16_384, rate_limit_per_minute: 120, rate_burst: 40,
                     trust_proxy: false)
        super(cors_origins: cors_origins.dup.freeze, max_body_bytes: max_body_bytes,
              rate_limit_per_minute: rate_limit_per_minute, rate_burst: rate_burst, trust_proxy: trust_proxy)
        freeze
      end
    end

    class Config
      ORIGIN = %r{\Ahttps?://[A-Za-z0-9.-]+(?::\d{1,5})?\z}
      private_constant :ORIGIN

      class << self
        # Reads and validates the settings.
        #
        # @param env [#[]] normally +ENV+
        # @return [Config]
        # @raise [ConfigError] naming the offending variable
        def from_env(env = ENV)
          new(
            cors_origins: origins(env["BRKIT_CORS_ORIGIN"]),
            max_body_bytes: integer(env, "BRKIT_MAX_BODY_BYTES", 16_384, 1..1_048_576),
            rate_limit_per_minute: integer(env, "BRKIT_RATE_LIMIT", 120, 0..100_000),
            rate_burst: integer(env, "BRKIT_RATE_BURST", 40, 1..10_000),
            trust_proxy: %w[1 true yes].include?(env["BRKIT_TRUST_PROXY"].to_s.downcase)
          )
        end

        private

        def origins(value)
          list = value.to_s.split(",").map(&:strip).reject(&:empty?)
          bad = list.find { |origin| origin != "*" && !origin.match?(ORIGIN) }
          if bad
            raise ConfigError, "BRKIT_CORS_ORIGIN: #{bad.inspect} is not an origin such as https://example.com or *"
          end
          if list.include?("*") && list.length > 1
            raise ConfigError, "BRKIT_CORS_ORIGIN: '*' cannot be combined with other origins"
          end

          list
        end

        def integer(env, name, default, range)
          raw = env[name]
          return default if raw.nil? || raw.strip.empty?

          value = Integer(raw.strip, 10)
          return value if range.cover?(value)

          raise ConfigError, "#{name} must be between #{range.min} and #{range.max}, got #{value}"
        rescue ArgumentError
          raise ConfigError, "#{name} must be an integer, got #{raw.to_s[0, 40].inspect}"
        end
      end
    end
  end
end
