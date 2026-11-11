# frozen_string_literal: true

require_relative "../version"
require_relative "params"

module Brkit
  module API
    # Builds the OpenAPI 3.1 description from the route table.
    #
    # Paths, parameters, request bodies and the list of error responses come from the {Route} declarations, so
    # the document cannot drift from what the server accepts.
    module OpenAPI
      PROBLEM_REF = { "$ref" => "#/components/responses/Problem" }.freeze

      ISSUE = {
        "type" => "object", "required" => %w[code message],
        "properties" => {
          "code" => { "type" => "string", "example" => "checksum" },
          "message" => { "type" => "string" },
          "field" => { "type" => "string", "description" => "The input field the problem refers to, when known." }
        }
      }.freeze

      RESULT = {
        "type" => "object", "required" => %w[kind input valid normalized formatted errors details],
        "properties" => {
          "kind" => { "type" => "string", "example" => "cpf" },
          "input" => { "type" => "string", "description" => "The value as received." },
          "valid" => { "type" => "boolean" },
          "normalized" => { "type" => %w[string null], "description" => "Canonical form, when the shape allows it." },
          "formatted" => { "type" => %w[string null], "description" => "Display form, when the shape allows it." },
          "errors" => { "type" => "array", "items" => { "$ref" => "#/components/schemas/Issue" } },
          "details" => { "type" => "object", "additionalProperties" => true,
                         "description" => "Document specific facts: region, brand, checksum steps, TLV tree, ..." }
        }
      }.freeze

      GENERATED = {
        "type" => "object", "required" => %w[kind seed count items],
        "properties" => {
          "kind" => { "type" => "string", "example" => "cpf" },
          "seed" => { "type" => "integer", "description" => "Seed used; pass it back to reproduce the items." },
          "count" => { "type" => "integer" },
          "items" => { "type" => "array", "items" => { "oneOf" => [{ "type" => "string" }, { "type" => "object" }] } }
        }
      }.freeze

      PIX_FIELD = {
        "type" => "object", "required" => %w[id length value],
        "properties" => {
          "id" => { "type" => "string", "pattern" => "^[0-9]{2}$", "example" => "26" },
          "name" => { "type" => "string", "example" => "Merchant Account Information" },
          "length" => { "type" => "integer" },
          "value" => { "type" => "string" },
          "children" => { "type" => "array", "items" => { "$ref" => "#/components/schemas/PixField" } }
        }
      }.freeze

      PIX_PAYLOAD = {
        "type" => "object", "required" => %w[payload crc key_type fields],
        "properties" => {
          "payload" => { "type" => "string", "description" => "The copia-e-cola text." },
          "crc" => { "type" => "string", "pattern" => "^[0-9A-F]{4}$", "example" => "1D3D" },
          "key_type" => { "type" => "string", "enum" => %w[cpf cnpj phone email evp] },
          "fields" => { "type" => "array", "items" => { "$ref" => "#/components/schemas/PixField" } }
        }
      }.freeze

      PERSON = {
        "type" => "object",
        "properties" => {
          "name" => { "type" => "string" }, "gender" => { "type" => "string", "enum" => %w[F M] },
          "cpf" => { "type" => "string" }, "email" => { "type" => "string" },
          "phone" => { "type" => "string" }, "phone_e164" => { "type" => "string" },
          "birthdate" => { "type" => "string", "format" => "date" },
          "address" => {
            "type" => "object",
            "properties" => {
              "street" => { "type" => "string" }, "number" => { "type" => "string" },
              "complement" => { "type" => %w[string null] }, "neighborhood" => { "type" => "string" },
              "city" => { "type" => "string" }, "uf" => { "type" => "string" }, "cep" => { "type" => "string" }
            }
          }
        }
      }.freeze

      PEOPLE = {
        "type" => "object", "required" => %w[kind seed count items],
        "properties" => {
          "kind" => { "type" => "string", "example" => "person" }, "seed" => { "type" => "integer" },
          "count" => { "type" => "integer" },
          "items" => { "type" => "array", "items" => { "$ref" => "#/components/schemas/Person" } }
        }
      }.freeze

      HEALTH = {
        "type" => "object", "required" => %w[status version],
        "properties" => { "status" => { "type" => "string", "example" => "ok" },
                          "version" => { "type" => "string", "example" => Brkit::VERSION } }
      }.freeze

      PROBLEM = {
        "type" => "object", "required" => %w[type title status],
        "description" => "RFC 9457 problem details.",
        "properties" => {
          "type" => { "type" => "string", "format" => "uri" }, "title" => { "type" => "string" },
          "status" => { "type" => "integer" }, "detail" => { "type" => "string" },
          "request_id" => { "type" => "string" },
          "errors" => { "type" => "array", "items" => { "$ref" => "#/components/schemas/Issue" } }
        }
      }.freeze

      SCHEMAS = {
        "Issue" => ISSUE, "Result" => RESULT, "Generated" => GENERATED, "PixField" => PIX_FIELD,
        "PixPayload" => PIX_PAYLOAD, "Person" => PERSON, "People" => PEOPLE, "Health" => HEALTH,
        "Problem" => PROBLEM,
        "OpenApiDocument" => { "type" => "object", "description" => "An OpenAPI 3.1 document." }
      }.freeze

      # Route#response => schema name
      RESPONSE_SCHEMAS = {
        result: "Result", generated: "Generated", pix_payload: "PixPayload", people: "People", health: "Health",
        openapi: "OpenApiDocument"
      }.freeze

      DESCRIPTION = <<~TEXT.strip
        Validators, generators and formatters for the documents and payloads Brazilian apps handle: CPF, CNPJ
        (classic and alphanumeric), PIS, PIX BR Codes, card numbers, licence plates, phone numbers, CEP, and
        seeded fictitious people. Offline and deterministic: nothing is looked up, and every generator is
        reproducible from a seed. Errors use RFC 9457 problem details (application/problem+json). Requests are
        rate limited per client address.
      TEXT

      class << self
        # @param routes [Array<Route>] the route table
        # @return [Hash] the OpenAPI document (string keys, ready for +JSON.generate+)
        def build(routes)
          {
            "openapi" => "3.1.0",
            "info" => info,
            "servers" => [{ "url" => "/" }],
            "tags" => routes.map(&:tag).uniq.map { |name| { "name" => name } },
            "paths" => paths(routes),
            "components" => { "schemas" => SCHEMAS, "responses" => { "Problem" => problem_response } }
          }
        end

        # @param param [Param]
        # @return [Hash] the JSON Schema of one parameter
        def schema(param)
          limit = param.max_length || Params::DEFAULT_MAX_LENGTH
          schema = case param.type
                   when :string then { "type" => "string", "maxLength" => limit }
                   when :integer then { "type" => "integer" }
                   when :boolean then { "type" => "boolean" }
                   else { "oneOf" => [{ "type" => "number" }, { "type" => "string", "maxLength" => limit }] }
                   end
          schema["enum"] = param.enum if param.enum
          schema["minimum"] = param.min if param.min
          schema["maximum"] = param.max if param.max
          schema["default"] = param.default unless param.default.nil?
          schema
        end

        private

        def info
          {
            "title" => "BRKit API", "version" => Brkit::VERSION,
            "summary" => "Brazilian document validators, generators and formatters",
            "description" => DESCRIPTION,
            "license" => { "name" => "MIT", "identifier" => "MIT" }
          }
        end

        def paths(routes)
          routes.group_by(&:path).transform_values do |list|
            list.to_h { |route| [route.verb.downcase, operation(route)] }
          end
        end

        def operation(route)
          operation = { "operationId" => route.operation_id, "summary" => route.summary, "tags" => [route.tag] }
          operation["description"] = route.description if route.description
          operation["parameters"] = route.params.map { |param| parameter(param) } unless route.params.empty?
          operation["requestBody"] = request_body(route.body) if route.body
          operation["responses"] = responses(route)
          operation
        end

        def parameter(param)
          { "name" => param.name.to_s, "in" => "query", "required" => param.required,
            "description" => param.description, "schema" => schema(param), "example" => param.example }.compact
        end

        def request_body(fields)
          properties = fields.to_h do |field|
            [field.name.to_s, schema(field).merge("description" => field.description).compact]
          end
          example = fields.select(&:example).to_h { |field| [field.name.to_s, field.example] }
          { "required" => true,
            "content" => { "application/json" => {
              "schema" => { "type" => "object", "additionalProperties" => false,
                            "required" => fields.select(&:required).map { |field| field.name.to_s },
                            "properties" => properties },
              "example" => example
            } } }
        end

        def responses(route)
          ok = { "description" => "OK",
                 "content" => { "application/json" => {
                   "schema" => { "$ref" => "#/components/schemas/#{RESPONSE_SCHEMAS.fetch(route.response)}" }
                 } } }
          codes = %w[406 500]
          codes << "400" unless route.params.empty? && route.body.nil?
          codes << "429" unless route.path == "/healthz"
          codes.push("413", "415", "422") if route.body
          codes.sort.each_with_object("200" => ok) { |code, list| list[code] = PROBLEM_REF }
        end

        def problem_response
          { "description" => "A problem details document.",
            "content" => { "application/problem+json" => { "schema" => { "$ref" => "#/components/schemas/Problem" } } } }
        end
      end
    end
  end
end
