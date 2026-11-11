# frozen_string_literal: true

require_relative "../test_helper"
require "brkit/api"

module Brkit
  module API
    class ConfigTest < Minitest::Test
      def test_defaults
        config = Config.new
        assert_equal [[], 16_384, 120, 40, false], [config.cors_origins, config.max_body_bytes,
                                                    config.rate_limit_per_minute, config.rate_burst, config.trust_proxy]
        assert_predicate config, :frozen?
        assert_predicate config.cors_origins, :frozen?
      end

      def test_an_empty_environment_gives_the_defaults
        assert_equal Config.new, Config.from_env({})
      end

      def test_reads_every_variable
        config = Config.from_env(
          "BRKIT_CORS_ORIGIN" => "https://a.example, http://localhost:3000", "BRKIT_MAX_BODY_BYTES" => "2048",
          "BRKIT_RATE_LIMIT" => "30", "BRKIT_RATE_BURST" => "5", "BRKIT_TRUST_PROXY" => "1"
        )
        assert_equal ["https://a.example", "http://localhost:3000"], config.cors_origins
        assert_equal [2048, 30, 5, true], [config.max_body_bytes, config.rate_limit_per_minute, config.rate_burst,
                                           config.trust_proxy]
      end

      def test_cors_origin_forms
        assert_equal ["*"], Config.from_env("BRKIT_CORS_ORIGIN" => "*").cors_origins
        assert_equal [], Config.from_env("BRKIT_CORS_ORIGIN" => "").cors_origins
        assert_equal [], Config.from_env("BRKIT_CORS_ORIGIN" => " , ").cors_origins
        assert_equal ["https://a.example"], Config.from_env("BRKIT_CORS_ORIGIN" => " https://a.example ").cors_origins
        assert_equal ["http://127.0.0.1:9292"], Config.from_env("BRKIT_CORS_ORIGIN" => "http://127.0.0.1:9292").cors_origins
      end

      def test_invalid_cors_origins_are_refused
        ["example.com", "https://", "https://a.example/path", "ftp://a.example", "https://a.example:99999x", "null",
         "https://a b", "javascript:alert(1)", "*.example.com", "https://a.example, nope"].each do |value|
          error = assert_raises(ConfigError, value) { Config.from_env("BRKIT_CORS_ORIGIN" => value) }
          assert_includes error.message, "BRKIT_CORS_ORIGIN"
        end
      end

      def test_wildcard_cannot_be_combined
        error = assert_raises(ConfigError) { Config.from_env("BRKIT_CORS_ORIGIN" => "*, https://a.example") }
        assert_includes error.message, "cannot be combined"
      end

      def test_numeric_ranges
        {
          "BRKIT_MAX_BODY_BYTES" => { ok: %w[1 1048576], bad: %w[0 1048577 -5] },
          "BRKIT_RATE_LIMIT" => { ok: %w[0 100000], bad: %w[-1 100001] },
          "BRKIT_RATE_BURST" => { ok: %w[1 10000], bad: %w[0 10001] }
        }.each do |name, cases|
          cases[:ok].each { |value| assert_kind_of Config, Config.from_env(name => value), "#{name}=#{value}" }
          cases[:bad].each do |value|
            error = assert_raises(ConfigError, "#{name}=#{value}") { Config.from_env(name => value) }
            assert_includes error.message, name
          end
        end
      end

      def test_non_numeric_values_are_refused
        ["abc", "1.5", "1e3", "0x10", "12 34"].each do |value|
          error = assert_raises(ConfigError, value) { Config.from_env("BRKIT_RATE_LIMIT" => value) }
          assert_includes error.message, "must be an integer"
        end
      end

      def test_blank_values_fall_back_to_the_default
        config = Config.from_env("BRKIT_RATE_LIMIT" => "  ", "BRKIT_MAX_BODY_BYTES" => "")
        assert_equal [120, 16_384], [config.rate_limit_per_minute, config.max_body_bytes]
      end

      def test_trust_proxy_values
        %w[1 true TRUE yes Yes].each { |value| assert Config.from_env("BRKIT_TRUST_PROXY" => value).trust_proxy, value }
        %w[0 false no off maybe].each { |value| refute Config.from_env("BRKIT_TRUST_PROXY" => value).trust_proxy, value }
      end

      def test_config_errors_belong_to_the_library_hierarchy
        assert_operator ConfigError, :<, Brkit::Error
      end
    end
  end
end
