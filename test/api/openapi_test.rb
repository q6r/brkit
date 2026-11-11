# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../support/rack_helpers"
require "brkit/api"

module Brkit
  module API
    class OpenAPITest < Minitest::Test
      VERBS = %w[get post].freeze

      def routes
        @routes ||= Endpoints.build.routes
      end

      def document
        @document ||= OpenAPI.build(routes)
      end

      def operations
        document["paths"].flat_map { |path, verbs| verbs.map { |verb, operation| [path, verb, operation] } }
      end

      def test_it_is_an_openapi_3_1_document
        assert_equal "3.1.0", document["openapi"]
        assert_equal Brkit::VERSION, document["info"]["version"]
        assert_equal "MIT", document["info"]["license"]["identifier"]
        assert_equal [{ "url" => "/" }], document["servers"]
      end

      def test_every_route_is_described_exactly_once
        described = operations.map { |path, verb, _operation| [verb.upcase, path] }
        assert_equal routes.map { |route| [route.verb, route.path] }.sort, described.sort
        assert_equal described.uniq, described
      end

      def test_operation_ids_are_unique_and_tags_are_declared
        ids = operations.map { |_path, _verb, operation| operation["operationId"] }
        assert_equal ids.uniq, ids
        declared = document["tags"].map { |tag| tag["name"] }
        operations.each { |_path, _verb, operation| (operation["tags"] - declared).then { |missing| assert_empty missing } }
      end

      def test_only_the_verbs_the_api_implements_appear
        operations.each { |path, verb, _operation| assert_includes VERBS, verb, "#{path} documents #{verb}" }
      end

      def test_parameters_mirror_the_declarations_of_the_route
        routes.each do |route|
          operation = document["paths"].fetch(route.path).fetch(route.verb.downcase)
          documented = Array(operation["parameters"]).to_h { |parameter| [parameter["name"], parameter] }
          assert_equal route.params.map { |param| param.name.to_s }.sort, documented.keys.sort, route.path
          route.params.each do |param|
            assert_equal param.required, documented.fetch(param.name.to_s)["required"], "#{route.path} #{param.name}"
            assert_value param.enum, documented.fetch(param.name.to_s)["schema"]["enum"]
          end
        end
      end

      def test_request_bodies_list_their_fields_and_forbid_extras
        routes.select(&:body).each do |route|
          schema = document["paths"].fetch(route.path).fetch("post")["requestBody"]["content"]["application/json"]["schema"]
          assert_equal false, schema["additionalProperties"]
          assert_equal route.body.map { |field| field.name.to_s }.sort, schema["properties"].keys.sort
          assert_equal route.body.select(&:required).map { |field| field.name.to_s }.sort, schema["required"].sort
        end
      end

      def test_the_pix_decode_body_offers_explain
        schema = document["paths"]["/api/v1/pix/decode"]["post"]["requestBody"]["content"]["application/json"]["schema"]
        assert_equal({ "type" => "boolean", "default" => false }, schema["properties"]["explain"].slice("type", "default"))
      end

      def test_every_reference_resolves
        refs = []
        walk = lambda do |node|
          case node
          when Hash then node.each { |key, value| key == "$ref" ? refs << value : walk.call(value) }
          when Array then node.each { |value| walk.call(value) }
          end
        end
        walk.call(document)
        refute_empty refs
        refs.each do |ref|
          *path, name = ref.delete_prefix("#/").split("/")
          assert document.dig(*path)&.key?(name), "dangling reference #{ref}"
        end
      end

      def test_every_failure_mode_is_a_documented_problem_response
        operations.each do |path, _verb, operation|
          codes = operation["responses"].keys
          assert_includes codes, "200", path
          assert_includes codes, "500", path
          assert_includes codes, "429", path unless path == "/healthz"
        end
      end

      def test_the_served_document_is_the_generated_one
        reply = request(App.new(config: Config.new(rate_limit_per_minute: 0), public_dir: "/nonexistent"), :get,
                        "/api/v1/openapi.json")
        assert_equal 200, reply.status
        assert_equal JSON.parse(JSON.generate(document)), reply.json
      end
    end
  end
end
