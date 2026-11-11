# frozen_string_literal: true

module Brkit
  module API
    # One endpoint of the API: where it lives, how it is documented and what it does.
    #
    # @!attribute [r] verb
    #   @return [String] HTTP method, +"GET"+ or +"POST"+
    # @!attribute [r] path
    #   @return [String] exact path such as +"/api/v1/cpf/validate"+
    # @!attribute [r] operation_id
    #   @return [String] unique id used by the OpenAPI document
    # @!attribute [r] summary
    #   @return [String] one-line description
    # @!attribute [r] description
    #   @return [String, nil] longer text
    # @!attribute [r] tag
    #   @return [String] group in the OpenAPI document
    # @!attribute [r] params
    #   @return [Array<Param>] query parameters
    # @!attribute [r] body
    #   @return [Array<Param>, nil] JSON body fields (POST routes)
    # @!attribute [r] response
    #   @return [Symbol] name of the response schema in {OpenAPI}
    # @!attribute [r] handler
    #   @return [#call] receives a {Context} and returns the JSON payload
    Route = Struct.new(:verb, :path, :operation_id, :summary, :description, :tag, :params, :body, :response,
                       :handler, keyword_init: true)

    # What a handler receives.
    #
    # @!attribute [r] params
    #   @return [Hash{Symbol=>Object}] validated query parameters
    # @!attribute [r] body
    #   @return [Hash{Symbol=>Object}] validated JSON body (empty for GET)
    # @!attribute [r] request
    #   @return [Request]
    Context = Struct.new(:params, :body, :request, keyword_init: true)

    # The route table: the single source of truth for dispatching and for the OpenAPI document.
    class Router
      # @return [Array<Route>] routes in registration order
      attr_reader :routes

      def initialize
        @routes = []
        @index = {}
      end

      # Registers a route.
      #
      # @param verb [String] +"GET"+ or +"POST"+
      # @param path [String]
      # @param handler [Proc] called with a {Context}, returns a JSON-serialisable payload
      # @return [Route]
      # @raise [ArgumentError] for a duplicate method and path or a duplicate operation id
      def add(verb, path, operation_id:, summary:, tag:, response:, description: nil, params: [], body: nil,
              &handler)
        raise ArgumentError, "duplicate route #{verb} #{path}" if @index.dig(path, verb)
        if @routes.any? { |route| route.operation_id == operation_id }
          raise ArgumentError, "duplicate operation id #{operation_id}"
        end

        route = Route.new(verb: verb, path: path, operation_id: operation_id, summary: summary,
                          description: description, tag: tag, params: params.freeze, body: body&.freeze,
                          response: response, handler: handler)
        @routes << route
        (@index[path] ||= {})[verb] = route
        route
      end

      # @see #add
      def get(path, **options, &handler)
        add("GET", path, **options, &handler)
      end

      # @see #add
      def post(path, **options, &handler)
        add("POST", path, **options, &handler)
      end

      # @param path [String] decoded request path
      # @return [Hash{String=>Route}, nil] the routes registered for +path+, by method
      def lookup(path)
        @index[path]
      end

      # @param path [String]
      # @return [Array<String>] methods answered on +path+; +HEAD+ comes with +GET+, +OPTIONS+ is always there
      def allowed_methods(path)
        methods = (@index[path] || {}).keys
        methods |= ["HEAD"] if methods.include?("GET")
        (methods | ["OPTIONS"]).sort
      end
    end
  end
end
