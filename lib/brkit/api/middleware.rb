# frozen_string_literal: true

require "securerandom"

require_relative "problem"
require_relative "request"
require_relative "response"

module Brkit
  module API
    # Rack middleware used by {App}. Each one is a small class with the usual +initialize(app, ...)+ and
    # +call(env)+, so they also work in any other Rack stack.
    module Middleware
      # Gives every request an id, echoed in the +x-request-id+ response header and in problem documents. A
      # client-supplied id is kept only when it is 8 to 64 characters of letters, digits, dot, dash or underscore
      # (anything else could smuggle control characters into logs and headers).
      class RequestId
        HEADER = "x-request-id"
        ACCEPTABLE = /\A[A-Za-z0-9._-]{8,64}\z/

        # @param app [#call]
        # @param generator [#call] returns a fresh id
        def initialize(app, generator: -> { SecureRandom.uuid })
          @app = app
          @generator = generator
        end

        def call(env)
          incoming = env["HTTP_X_REQUEST_ID"].to_s
          id = incoming.match?(ACCEPTABLE) ? incoming : @generator.call
          env[Request::REQUEST_ID_KEY] = id
          status, headers, body = @app.call(env)
          [status, headers.merge(HEADER => id), body]
        end
      end

      # Adds browser-hardening headers to every response unless the inner app already set them.
      class SecureHeaders
        DEFAULTS = {
          "x-content-type-options" => "nosniff",
          "referrer-policy" => "no-referrer",
          "x-frame-options" => "DENY"
        }.freeze

        def initialize(app)
          @app = app
        end

        def call(env)
          status, headers, body = @app.call(env)
          [status, DEFAULTS.merge(headers), body]
        end
      end

      # Optional CORS support, off unless origins are configured (+BRKIT_CORS_ORIGIN+).
      #
      # A request from an allowed origin gets +access-control-allow-origin+ (the origin itself, or +*+ when
      # configured so); preflight requests are answered here with a 204. Origins are compared exactly; no
      # credentials are ever allowed.
      class Cors
        ALLOWED_METHODS = "GET, POST, OPTIONS"
        ALLOWED_HEADERS = "content-type, accept, x-request-id"
        EXPOSED_HEADERS = "x-request-id, ratelimit-limit, ratelimit-remaining, ratelimit-reset, retry-after"
        MAX_AGE = "600"

        # @param app [#call]
        # @param origins [Array<String>] allowed origins, or +["*"]+; empty turns CORS off
        def initialize(app, origins:)
          @app = app
          @origins = origins
        end

        def call(env)
          origin = env["HTTP_ORIGIN"]
          return @app.call(env) if @origins.empty? || origin.nil?
          return preflight(origin) if preflight?(env)

          status, headers, body = @app.call(env)
          [status, decorate(headers, origin), body]
        end

        private

        def allowed?(origin)
          @origins.include?("*") || @origins.include?(origin)
        end

        def preflight?(env)
          env["REQUEST_METHOD"] == "OPTIONS" && env.key?("HTTP_ACCESS_CONTROL_REQUEST_METHOD")
        end

        def preflight(origin)
          headers = { "vary" => "origin, access-control-request-method, access-control-request-headers" }
          if allowed?(origin)
            headers.merge!(allow_origin(origin), "access-control-allow-methods" => ALLOWED_METHODS,
                                                 "access-control-allow-headers" => ALLOWED_HEADERS,
                                                 "access-control-max-age" => MAX_AGE)
          end
          Response.bare(204, headers)
        end

        def decorate(headers, origin)
          return headers.merge("vary" => "origin") unless allowed?(origin)

          headers.merge(allow_origin(origin), "access-control-expose-headers" => EXPOSED_HEADERS)
        end

        def allow_origin(origin)
          return { "access-control-allow-origin" => "*" } if @origins.include?("*")

          { "access-control-allow-origin" => origin, "vary" => "origin" }
        end
      end

      # Rejects requests whose declared body is larger than the limit before reading anything, and publishes
      # the limit for {Request#body}, which enforces it while reading (chunked bodies declare no length).
      class BodyLimit
        # @param max_bytes [Integer]
        def initialize(app, max_bytes:)
          @app = app
          @max_bytes = max_bytes
        end

        def call(env)
          env[Request::BODY_LIMIT_KEY] = @max_bytes
          declared = Request.new(env).content_length
          raise Problem.payload_too_large(@max_bytes) if declared && declared > @max_bytes

          @app.call(env)
        end
      end

      # A per-client token bucket: +capacity+ requests may arrive in a burst, then +per_minute+ requests per
      # minute are sustained. State lives in memory (one process); clients beyond +max_clients+ are forgotten
      # oldest first, which at worst grants a fresh bucket. Time comes from an injectable monotonic clock.
      class TokenBucket
        # Outcome of one {#take}.
        Decision = Struct.new(:allowed, :limit, :remaining, :reset, :retry_after, keyword_init: true) do
          # @return [Hash{String=>String}] IETF draft rate-limit headers
          def headers
            { "ratelimit-limit" => limit.to_s, "ratelimit-remaining" => remaining.to_s, "ratelimit-reset" => reset.to_s }
          end
        end

        # @param capacity [Integer] bucket size
        # @param per_minute [Numeric] refill rate
        # @param clock [#call] returns monotonic seconds
        # @param max_clients [Integer] how many client buckets to remember
        def initialize(capacity:, per_minute:, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) },
                       max_clients: 10_000)
          raise ArgumentError, "capacity and per_minute must be positive" unless capacity.positive? && per_minute.positive?

          @capacity = capacity.to_f
          @rate = per_minute / 60.0
          @clock = clock
          @max_clients = max_clients
          @buckets = {}
          @lock = Mutex.new
        end

        # Takes one token for +key+.
        #
        # @param key [String] client identifier
        # @return [Decision]
        def take(key)
          @lock.synchronize do
            now = @clock.call
            tokens = refill(@buckets.delete(key), now)
            allowed = tokens >= 1.0
            tokens -= 1.0 if allowed
            @buckets[key] = [tokens, now]
            @buckets.shift while @buckets.size > @max_clients
            decision(allowed, tokens)
          end
        end

        # @return [Integer] how many clients are remembered
        def size
          @lock.synchronize { @buckets.size }
        end

        private

        def refill(bucket, now)
          return @capacity unless bucket

          tokens, stamp = bucket
          [@capacity, tokens + ((now - stamp) * @rate)].min
        end

        def decision(allowed, tokens)
          Decision.new(allowed: allowed, limit: @capacity.to_i, remaining: [tokens.floor, 0].max,
                       reset: ((@capacity - tokens) / @rate).ceil,
                       retry_after: allowed ? 0 : [((1.0 - tokens) / @rate).ceil, 1].max)
        end
      end

      # Applies a {TokenBucket} per client address and answers 429 (with +retry-after+) when it is empty.
      # Successful responses carry +ratelimit-limit+, +ratelimit-remaining+ and +ratelimit-reset+.
      class RateLimit
        # @param limiter [TokenBucket]
        # @param trust_proxy [Boolean] key on the right-most +X-Forwarded-For+ entry instead of +REMOTE_ADDR+
        # @param exempt [Array<String>] raw paths that are never limited (health checks)
        # @param scope [Regexp, nil] when given, only paths that match are limited (so that loading the playground's
        #   own files does not spend the API budget)
        def initialize(app, limiter:, trust_proxy: false, exempt: ["/healthz"], scope: nil)
          @app = app
          @limiter = limiter
          @trust_proxy = trust_proxy
          @exempt = exempt
          @scope = scope
        end

        def call(env)
          path = env["PATH_INFO"].to_s
          return @app.call(env) if @exempt.include?(path) || (@scope && !path.match?(@scope))

          decision = @limiter.take(Request.new(env).ip(trust_proxy: @trust_proxy))
          raise Problem.rate_limited(decision.retry_after, decision.headers) unless decision.allowed

          status, headers, body = @app.call(env)
          [status, decision.headers.merge(headers), body]
        end
      end

      # Turns exceptions into problem documents: {Problem} as itself, {InvalidInputError} as 422, anything
      # else as an opaque 500 (details go to the log, never to the client).
      class ErrorBoundary
        # @param logger [#error, nil] receives unexpected errors; defaults to the Rack error stream
        def initialize(app, logger: nil)
          @app = app
          @logger = logger
        end

        def call(env)
          @app.call(env)
        rescue Problem => e
          respond(env, e)
        rescue InvalidInputError => e
          respond(env, Problem.validation(e.issues))
        rescue StandardError => e
          log(env, e)
          respond(env, Problem.new("internal-error", "an unexpected error occurred; quote the request id when " \
                                                    "reporting it"))
        end

        private

        def respond(env, problem)
          Response.problem(problem, request_id: env[Request::REQUEST_ID_KEY])
        end

        def log(env, error)
          trace = (error.backtrace || []).first(8).join("\n  ")
          line = "[brkit] request #{env[Request::REQUEST_ID_KEY]} failed: #{error.class}: #{error.message}\n  #{trace}"
          if @logger
            @logger.error(line)
          elsif (stream = env["rack.errors"])
            stream.puts(line)
            stream.flush if stream.respond_to?(:flush)
          end
        end
      end
    end
  end
end
