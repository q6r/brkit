# frozen_string_literal: true

require "securerandom"

require_relative "config"
require_relative "endpoints"
require_relative "middleware"
require_relative "params"
require_relative "problem"
require_relative "request"
require_relative "response"
require_relative "router"
require_relative "static"

module Brkit
  module API
    # Maps a request to a route handler or a static file. It raises {Problem} for anything that is not a
    # success; {Middleware::ErrorBoundary} renders those.
    class Dispatcher
      # @param router [Router]
      # @param static [Static]
      def initialize(router, static)
        @router = router
        @static = static
      end

      def call(env)
        request = Request.new(env)
        path = request.path
        verb = request.http_method
        routes = @router.lookup(path)
        return route_response(request, routes, verb) if routes
        raise Problem.new("not-found", "no such endpoint; see /api/v1/openapi.json") if api_path?(path)

        static_response(request, verb)
      end

      private

      def api_path?(path)
        path == "/api" || path.start_with?("/api/")
      end

      def route_response(request, routes, verb)
        return Response.bare(204, "allow" => @router.allowed_methods(request.path).join(", ")) if verb == "OPTIONS"

        route = routes[verb == "HEAD" ? "GET" : verb]
        raise Problem.method_not_allowed(verb, @router.allowed_methods(request.path)) unless route
        unless request.accepts?(Response::JSON_TYPE)
          raise Problem.new("not-acceptable", "this endpoint only produces #{Response::JSON_TYPE}")
        end

        response = Response.json(run(route, request))
        verb == "HEAD" ? Response.without_body(response) : response
      end

      def run(route, request)
        params = Params.from_query(route.params, request.query)
        body = route.body ? Params.from_body(route.body, request.json_body) : {}
        route.handler.call(Context.new(params: params, body: body, request: request))
      end

      def static_response(request, verb)
        case verb
        when "GET", "HEAD" then @static.call(request) || raise(Problem.new("not-found", "no such resource"))
        when "OPTIONS" then Response.bare(204, "allow" => "GET, HEAD, OPTIONS")
        else raise Problem.method_not_allowed(verb, %w[GET HEAD OPTIONS])
        end
      end
    end

    # The whole API as one Rack application: +App.new.call(env)+ returns +[status, headers, body]+.
    #
    # It speaks plain Rack and needs no gem at runtime, so any Rack 3 server can run it (see +config.ru+)
    # and tests can drive it with hand-built environments. The middleware stack, outermost first:
    # request id, security headers, CORS, error boundary, rate limit, body limit, dispatcher.
    #
    #   app = Brkit::API::App.new(config: Brkit::API::Config.new(rate_limit_per_minute: 0))
    #   env = { "REQUEST_METHOD" => "GET", "PATH_INFO" => "/healthz", "QUERY_STRING" => "" }
    #   status, headers, body = app.call(env) #=> [200, { "content-type" => "application/json", ... }, ["{...}"]]
    class App
      # The directory served as the playground (+public/+ at the project root).
      DEFAULT_PUBLIC_DIR = File.expand_path("../../../public", __dir__)

      # @return [Config]
      attr_reader :config
      # @return [Router]
      attr_reader :router

      # @param config [Config] settings; read from the environment by default
      # @param public_dir [String] directory of static files
      # @param clock [#call, nil] monotonic clock for the rate limiter (injectable for tests)
      # @param logger [#error, nil] receives unexpected errors
      # @param id_generator [#call, nil] request id source (injectable for tests)
      def initialize(config: Config.from_env, public_dir: DEFAULT_PUBLIC_DIR, clock: nil, logger: nil,
                     id_generator: nil)
        @config = config
        @router = Endpoints.build
        dispatcher = Dispatcher.new(@router, Static.new(root: public_dir))
        @stack = build_stack(dispatcher, clock: clock, logger: logger, id_generator: id_generator)
      end

      # @param env [Hash] a Rack environment
      # @return [Array] a Rack response triple; never raises
      def call(env)
        @stack.call(env)
      rescue StandardError
        Response.problem(Problem.new("internal-error", "an unexpected error occurred"))
      end

      private

      def build_stack(dispatcher, clock:, logger:, id_generator:)
        app = Middleware::BodyLimit.new(dispatcher, max_bytes: config.max_body_bytes)
        app = rate_limited(app, clock) if config.rate_limit_per_minute.positive?
        app = Middleware::ErrorBoundary.new(app, logger: logger)
        app = Middleware::Cors.new(app, origins: config.cors_origins)
        app = Middleware::SecureHeaders.new(app)
        Middleware::RequestId.new(app, generator: id_generator || -> { SecureRandom.uuid })
      end

      # Only the API is limited; the static playground files and /healthz are not.
      def rate_limited(app, clock)
        options = { capacity: config.rate_burst, per_minute: config.rate_limit_per_minute }
        options[:clock] = clock if clock
        Middleware::RateLimit.new(app, limiter: Middleware::TokenBucket.new(**options),
                                       trust_proxy: config.trust_proxy, scope: %r{\A/api/})
      end
    end
  end
end
