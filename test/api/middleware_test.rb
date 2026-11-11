# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../support/rack_helpers"
require "brkit/api"

module Brkit
  module API
    class MiddlewareTest < Minitest::Test
      # A clock the test moves by hand.
      class Clock
        attr_accessor :now

        def initialize(now = 1_000.0)
          @now = now
        end

        def call
          @now
        end
      end

      CPF_PATH = "/api/v1/cpf/generate"

      def app_with(clock: nil, **settings)
        App.new(config: Config.new(**settings), public_dir: "/nonexistent-brkit-public", clock: clock)
      end

      # -- token bucket ------------------------------------------------------------------------------------

      def test_the_bucket_allows_a_burst_then_refills_at_the_sustained_rate
        clock = Clock.new
        bucket = Middleware::TokenBucket.new(capacity: 3, per_minute: 60, clock: clock)

        decisions = Array.new(4) { bucket.take("a") }
        assert_equal [true, true, true, false], decisions.map(&:allowed)
        assert_equal [2, 1, 0, 0], decisions.map(&:remaining)
        assert_equal 1, decisions.last.retry_after

        clock.now += 1.0
        assert bucket.take("a").allowed
        refute bucket.take("a").allowed

        clock.now += 600.0
        assert_equal 2, bucket.take("a").remaining, "the bucket never holds more than its capacity"
      end

      def test_buckets_are_per_client_and_the_oldest_are_forgotten
        bucket = Middleware::TokenBucket.new(capacity: 1, per_minute: 60, clock: Clock.new, max_clients: 2)
        assert bucket.take("a").allowed
        assert bucket.take("b").allowed
        refute bucket.take("a").allowed
        bucket.take("c")
        assert_equal 2, bucket.size
      end

      def test_the_decision_exposes_rate_limit_headers
        decision = Middleware::TokenBucket.new(capacity: 5, per_minute: 60, clock: Clock.new).take("a")
        assert_equal({ "ratelimit-limit" => "5", "ratelimit-remaining" => "4", "ratelimit-reset" => "1" },
                     decision.headers)
      end

      def test_a_bucket_needs_positive_settings
        assert_raises(ArgumentError) { Middleware::TokenBucket.new(capacity: 0, per_minute: 60) }
        assert_raises(ArgumentError) { Middleware::TokenBucket.new(capacity: 5, per_minute: 0) }
      end

      # -- rate limit through the app -----------------------------------------------------------------------

      def test_the_limit_answers_429_with_a_retry_after
        clock = Clock.new
        app = app_with(clock: clock, rate_limit_per_minute: 60, rate_burst: 2)
        2.times { assert_equal 200, request(app, :get, CPF_PATH).status }

        limited = request(app, :get, CPF_PATH)
        assert_equal 429, limited.status
        assert_predicate limited, :problem?
        assert_equal "#{Problem::BASE_URI}rate-limited", limited.json["type"]
        assert_equal "1", limited.header("retry-after")
        assert_equal "0", limited.header("ratelimit-remaining")

        clock.now += 1.0
        assert_equal 200, request(app, :get, CPF_PATH).status
      end

      def test_successful_responses_report_the_remaining_budget
        app = app_with(clock: Clock.new, rate_limit_per_minute: 60, rate_burst: 5)
        reply = request(app, :get, CPF_PATH)
        assert_equal %w[5 4], [reply.header("ratelimit-limit"), reply.header("ratelimit-remaining")]
      end

      def test_the_health_probe_is_never_limited
        app = app_with(clock: Clock.new, rate_limit_per_minute: 60, rate_burst: 1)
        request(app, :get, CPF_PATH)
        5.times { assert_equal 200, request(app, :get, "/healthz").status }
      end

      def test_only_paths_in_scope_are_limited
        limiter = Middleware::TokenBucket.new(capacity: 1, per_minute: 60, clock: Clock.new)
        inner = ->(_env) { Response.json({}) }
        limited = Middleware::RateLimit.new(inner, limiter: limiter, scope: %r{\A/api/})

        3.times { assert_equal 200, limited.call(env_for("GET", "/index.html")).first }
        assert_equal 200, limited.call(env_for("GET", "/api/anything")).first
        assert_raises(Problem) { limited.call(env_for("GET", "/api/anything")) }
      end

      def test_clients_do_not_share_a_budget
        app = app_with(clock: Clock.new, rate_limit_per_minute: 60, rate_burst: 1)
        assert_equal 200, request(app, :get, CPF_PATH, ip: "203.0.113.1").status
        assert_equal 429, request(app, :get, CPF_PATH, ip: "203.0.113.1").status
        assert_equal 200, request(app, :get, CPF_PATH, ip: "203.0.113.2").status
      end

      def test_a_forwarded_address_is_ignored_unless_the_proxy_is_trusted
        spoofed = ->(value) { { "X-Forwarded-For" => value } }
        app = app_with(clock: Clock.new, rate_limit_per_minute: 60, rate_burst: 1)
        assert_equal 200, request(app, :get, CPF_PATH, headers: spoofed.call("198.51.100.1")).status
        assert_equal 429, request(app, :get, CPF_PATH, headers: spoofed.call("198.51.100.2")).status,
                     "changing the header must not buy a fresh bucket"

        trusting = app_with(clock: Clock.new, rate_limit_per_minute: 60, rate_burst: 1, trust_proxy: true)
        assert_equal 200, request(trusting, :get, CPF_PATH, headers: spoofed.call("10.0.0.9, 198.51.100.1")).status
        assert_equal 429, request(trusting, :get, CPF_PATH, headers: spoofed.call("10.0.0.8, 198.51.100.1")).status,
                     "only the right-most entry, written by the trusted proxy, counts"
        assert_equal 200, request(trusting, :get, CPF_PATH, headers: spoofed.call("198.51.100.2")).status
      end

      def test_a_limit_of_zero_turns_limiting_off
        app = app_with(rate_limit_per_minute: 0)
        60.times { assert_equal 200, request(app, :get, CPF_PATH).status }
        refute request(app, :get, CPF_PATH).headers.key?("ratelimit-limit")
      end

      # -- CORS ----------------------------------------------------------------------------------------------

      def test_cors_is_off_by_default
        reply = request(app_with(rate_limit_per_minute: 0), :get, CPF_PATH, headers: { "Origin" => "https://example.com" })
        refute reply.headers.key?("access-control-allow-origin")
      end

      def test_an_allowed_origin_is_echoed
        app = app_with(rate_limit_per_minute: 0, cors_origins: ["https://example.com"])
        reply = request(app, :get, CPF_PATH, headers: { "Origin" => "https://example.com" })
        assert_equal "https://example.com", reply.header("access-control-allow-origin")
        assert_equal "origin", reply.header("vary")
        assert_includes reply.header("access-control-expose-headers"), "x-request-id"
        refute reply.headers.key?("access-control-allow-credentials")
      end

      def test_other_origins_get_no_permission
        app = app_with(rate_limit_per_minute: 0, cors_origins: ["https://example.com"])
        ["https://evil.example", "http://example.com", "https://example.com.evil.example", "null"].each do |origin|
          reply = request(app, :get, CPF_PATH, headers: { "Origin" => origin })
          refute reply.headers.key?("access-control-allow-origin"), origin
          assert_equal "origin", reply.header("vary")
        end
      end

      def test_a_wildcard_allows_everyone_without_credentials
        app = app_with(rate_limit_per_minute: 0, cors_origins: ["*"])
        reply = request(app, :get, CPF_PATH, headers: { "Origin" => "https://anything.example" })
        assert_equal "*", reply.header("access-control-allow-origin")
        refute reply.headers.key?("access-control-allow-credentials")
      end

      def test_preflight_requests_are_answered_without_reaching_the_api
        app = app_with(rate_limit_per_minute: 0, cors_origins: ["https://example.com"])
        preflight = { "Origin" => "https://example.com", "Access-Control-Request-Method" => "POST" }
        reply = request(app, :options, "/api/v1/pix/decode", headers: preflight)
        assert_equal 204, reply.status
        assert_equal "https://example.com", reply.header("access-control-allow-origin")
        assert_equal "GET, POST, OPTIONS", reply.header("access-control-allow-methods")
        assert_includes reply.header("access-control-allow-headers"), "content-type"

        denied = request(app, :options, "/api/v1/pix/decode", headers: preflight.merge("Origin" => "https://evil.example"))
        assert_equal 204, denied.status
        refute denied.headers.key?("access-control-allow-origin")
      end

      # -- error boundary ------------------------------------------------------------------------------------

      def boundary_reply(error, logger: nil)
        inner = ->(_env) { raise error }
        env = env_for("GET", "/boom")
        status, headers, body = Middleware::ErrorBoundary.new(inner, logger: logger).call(env)
        parts = body.map { |part| part }
        RackHelpers::Reply.new(status, headers, parts.join)
      end

      def test_unexpected_errors_become_an_opaque_500_and_are_logged
        logged = []
        logger = Object.new
        logger.define_singleton_method(:error) { |line| logged << line }

        reply = boundary_reply(RuntimeError.new("database password is hunter2"), logger: logger)
        assert_equal 500, reply.status
        assert_predicate reply, :problem?
        refute_includes reply.body, "hunter2"
        assert_equal 1, logged.length
        assert_includes logged.first, "RuntimeError: database password is hunter2"
      end

      def test_without_a_logger_errors_go_to_the_rack_error_stream
        errors = StringIO.new
        env = env_for("GET", "/boom").merge("rack.errors" => errors)
        Middleware::ErrorBoundary.new(->(_env) { raise "kaput" }).call(env)
        assert_includes errors.string, "kaput"
      end

      def test_library_refusals_are_422s_and_problems_keep_their_status
        invalid = InvalidInputError.new([Issue.new(code: :blank, message: "key is empty", field: "key")])
        reply = boundary_reply(invalid)
        assert_equal 422, reply.status
        assert_equal "key", reply.json["errors"].first["field"]

        assert_equal 404, boundary_reply(Problem.new("not-found", "gone")).status
      end

      # -- body limit ----------------------------------------------------------------------------------------

      def test_an_oversized_declared_body_is_refused_before_it_is_read
        app = app_with(rate_limit_per_minute: 0, max_body_bytes: 100)
        reply = request(app, :post, "/api/v1/pix/decode", body: "x" * 101, headers: { "Content-Type" => "application/json" })
        assert_equal 413, reply.status
        assert_equal "#{Problem::BASE_URI}payload-too-large", reply.json["type"]
      end
    end
  end
end
