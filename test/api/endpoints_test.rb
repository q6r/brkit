# frozen_string_literal: true

require "uri"

require_relative "../test_helper"
require_relative "../support/rack_helpers"

module Brkit
  module API
    class EndpointsTest < Minitest::Test
      EVP = "123e4567-e12b-12d1-a456-426655440000"
      MANUAL_PAYLOAD = "00020126580014br.gov.bcb.pix0136123e4567-e12b-12d1-a456-4266554400005204000053039865802BR5913" \
                       "Fulano de Tal6008BRASILIA62070503***63041D3D"

      RESULT_KEYS = %w[kind input valid normalized formatted errors details].freeze

      VALIDATORS = {
        "cpf" => { param: "cpf", valid: "529.982.247-25", invalid: "529.982.247-26", explain: true },
        "cnpj" => { param: "cnpj", valid: "12.ABC.345/01DE-35", invalid: "11.222.333/0001-82", explain: true },
        "pis" => { param: "pis", valid: "123.45678.91-9", invalid: "123.45678.91-8", explain: true },
        "card" => { param: "number", valid: "4111 1111 1111 1111", invalid: "4111 1111 1111 1112", explain: true },
        "plate" => { param: "plate", valid: "ABC-1234", invalid: "AB-1234", explain: false },
        "phone" => { param: "phone", valid: "(11) 98765-4321", invalid: "(11) 8765-4321", explain: false },
        "cep" => { param: "cep", valid: "01310-100", invalid: "1234", explain: false }
      }.freeze

      LIBRARIES = { "cpf" => CPF, "cnpj" => CNPJ, "pis" => PIS, "card" => Card, "plate" => Plate, "phone" => Phone,
                    "cep" => CEP }.freeze

      def app
        @app ||= App.new(config: Config.new(rate_limit_per_minute: 0), public_dir: "/nonexistent-brkit-public")
      end

      # GET +path+; every keyword (or hash) argument becomes a query parameter.
      def get(path, params = {}, **query)
        request(app, :get, path, query: URI.encode_www_form(params.merge(query)))
      end

      def assert_problem(reply, status, slug)
        assert reply.problem?, "expected problem+json, got #{reply.header('content-type')}"
        assert_equal status, reply.status
        document = reply.json
        assert_equal ["#{Problem::BASE_URI}#{slug}", status], document.values_at("type", "status")
        assert_equal reply.header("x-request-id"), document["request_id"]
        refute_nil document["title"]
        document
      end

      # -- meta --------------------------------------------------------------------------------------------

      def test_health
        reply = get("/healthz")
        assert_equal 200, reply.status
        assert_equal({ "status" => "ok", "version" => Brkit::VERSION }, reply.json)
        assert_equal "application/json", reply.header("content-type")
      end

      # -- validators --------------------------------------------------------------------------------------

      def test_validate_endpoints_return_the_library_result
        VALIDATORS.each do |name, spec|
          [spec[:valid], spec[:invalid]].each do |value|
            reply = get("/api/v1/#{name}/validate", spec[:param] => value)
            assert_equal 200, reply.status, "#{name} #{value}"
            assert_equal RESULT_KEYS, reply.json.keys, name
            expected = JSON.parse(JSON.generate(LIBRARIES.fetch(name).validate(value).to_h))
            assert_equal expected, reply.json, "#{name} #{value}"
            assert_equal name, reply.json["kind"]
          end
          assert reply_valid?(name, spec[:valid])
          refute reply_valid?(name, spec[:invalid])
        end
      end

      def reply_valid?(name, value)
        get("/api/v1/#{name}/validate", VALIDATORS.fetch(name)[:param] => value).json["valid"]
      end

      def test_invalid_values_explain_themselves
        reply = get("/api/v1/cpf/validate", cpf: "529.982.247-26")
        error = reply.json["errors"].first
        assert_equal "checksum", error["code"]
        assert_includes error["message"], "second check digit"
        assert_equal "52998224726", reply.json["normalized"]
      end

      def test_explain_adds_the_checksum_steps
        VALIDATORS.each do |name, spec|
          next unless spec[:explain]

          steps = get("/api/v1/#{name}/validate", spec[:param] => spec[:valid], "explain" => "true").json["details"]["steps"]
          refute_nil steps, name
          without = get("/api/v1/#{name}/validate", spec[:param] => spec[:valid]).json["details"]
          refute without.key?("steps"), name
        end
        steps = get("/api/v1/cnpj/validate", cnpj: "12.ABC.345/01DE-35", explain: "1").json["details"]["steps"]
        assert_equal [1, 2, 17, 18, 19, 3, 4, 5, 0, 1, 20, 21], steps[0]["values"]
        assert_equal [459, 8, 3], steps[0].values_at("sum", "remainder", "check_digit")
      end

      def test_explain_is_not_offered_for_documents_without_steps
        %w[plate phone cep].each do |name|
          reply = get("/api/v1/#{name}/validate", VALIDATORS.fetch(name)[:param] => VALIDATORS.fetch(name)[:valid],
                                                  "explain" => "true")
          document = assert_problem(reply, 400, "invalid-parameter")
          assert_equal "unknown_parameter", document["errors"].first["code"]
        end
      end

      def test_the_cpf_region_is_reported
        details = get("/api/v1/cpf/validate", cpf: "529.982.247-25").json["details"]
        assert_equal 7, details["region_digit"]
        assert_equal %w[ES RJ], details["ufs"]
      end

      def test_pix_style_inputs_with_special_characters_survive_the_query_string
        reply = get("/api/v1/phone/validate", phone: "+55 (11) 98765-4321")
        assert_equal "+5511987654321", reply.json["normalized"]
        reply = request(app, :get, "/api/v1/cpf/validate", query: "cpf=529%2E982%2E247%2D25")
        assert reply.json["valid"]
      end

      def test_missing_and_oversized_parameters
        document = assert_problem(get("/api/v1/cpf/validate"), 400, "invalid-parameter")
        assert_equal [{ "code" => "missing", "message" => "cpf is required", "field" => "cpf" }], document["errors"]
        long = assert_problem(get("/api/v1/cpf/validate", cpf: "1" * 513), 400, "invalid-parameter")
        assert_equal "too_long", long["errors"].first["code"]
        medium = get("/api/v1/cpf/validate", cpf: "1" * 300)
        assert_equal 200, medium.status
        assert_equal "too_long", medium.json["errors"].first["code"], "the validator reports it, not the API"
      end

      def test_hostile_values_are_answered_not_fatal
        ["‮", "٥٢٩٩٨٢٢٤٧٢٥", "'; DROP TABLE x;--", "<script>alert(1)</script>", "${7*7}",
         "../../etc/passwd"].each do |value|
          reply = get("/api/v1/cpf/validate", cpf: value)
          assert_equal 200, reply.status, value
          refute reply.json["valid"]
          assert_equal value, reply.json["input"], "the input is echoed as JSON text, never interpreted"
        end
      end

      def test_invalid_percent_encoding_in_the_query_is_a_bad_request
        reply = request(app, :get, "/api/v1/cpf/validate", query: "cpf=%zz")
        assert_problem(reply, 400, "bad-request")
        assert_problem(request(app, :get, "/api/v1/cpf/validate", query: "cpf=%FF"), 400, "bad-request")
        assert_problem(request(app, :get, "/api/v1/cpf/validate", query: "cpf=1&cpf=2"), 400, "bad-request")
      end

      # -- generators --------------------------------------------------------------------------------------

      GENERATE_CHECKS = {
        "cpf" => ->(item) { CPF.valid?(item) },
        "cnpj" => ->(item) { CNPJ.valid?(item) },
        "pis" => ->(item) { PIS.valid?(item) },
        "plate" => ->(item) { Plate.valid?(item) },
        "phone" => ->(item) { Phone.valid?(item) },
        "cep" => ->(item) { CEP.valid?(item) },
        "card" => ->(item) { Card.valid?(item["number"]) && Card.detect(item["number"]).id == item["brand"] }
      }.freeze

      def test_generators_return_valid_items
        GENERATE_CHECKS.each do |name, check|
          document = get("/api/v1/#{name}/generate", count: 5, seed: 42).json
          assert_equal [name, 42, 5], document.values_at("kind", "seed", "count"), name
          assert_equal 5, document["items"].length
          document["items"].each { |item| assert check.call(item), "#{name}: #{item.inspect}" }
        end
      end

      def test_generation_is_reproducible_from_the_seed
        GENERATE_CHECKS.each_key do |name|
          first = get("/api/v1/#{name}/generate", count: 3, seed: 7).json
          again = get("/api/v1/#{name}/generate", count: 3, seed: 7).json
          other = get("/api/v1/#{name}/generate", count: 3, seed: 8).json
          assert_equal first, again, name
          refute_equal first["items"], other["items"], name
        end
      end

      def test_a_random_seed_is_echoed_and_reproduces_the_items
        3.times do
          first = get("/api/v1/cpf/generate", count: 4).json
          assert_includes 0..Rng::MAX_SEED, first["seed"]
          replay = get("/api/v1/cpf/generate", count: 4, seed: first["seed"]).json
          assert_equal first["items"], replay["items"]
        end
        refute_equal get("/api/v1/fake/person").json["seed"], get("/api/v1/fake/person").json["seed"]
      end

      def test_the_documented_cpf_example_is_stable
        reply = request(app, :get, "/api/v1/cpf/generate", query: "formatted=true&uf=SP&count=3&seed=42")
        assert_equal '{"kind":"cpf","seed":42,"count":3,"items":["637.469.268-31","437.725.418-95","514.095.808-22"]}',
                     reply.body
      end

      def test_default_count_is_one_and_the_maximum_is_one_hundred
        assert_equal 1, get("/api/v1/cpf/generate").json["items"].length
        assert_equal 100, get("/api/v1/cpf/generate", count: 100, seed: 1).json["items"].length
        assert_equal 100, get("/api/v1/fake/person", count: 100, seed: 1).json["items"].length
      end

      def test_generator_options
        formatted = get("/api/v1/cpf/generate", formatted: "true", uf: "sp", count: 20, seed: 3).json["items"]
        assert(formatted.all? { |cpf| cpf.match?(/\A\d{3}\.\d{3}\.\d{3}-\d{2}\z/) && CPF.region(cpf)[:ufs].include?("SP") })
        alnum = get("/api/v1/cnpj/generate", alphanumeric: "true", branch: "0002", count: 10, seed: 3, formatted: "true").json
        assert(alnum["items"].all? { |cnpj| cnpj.match?(%r{/0002-}) && CNPJ.validate(cnpj).details[:alphanumeric] })
        cards = get("/api/v1/card/generate", brand: "ELO", count: 5, seed: 3).json["items"]
        assert(cards.all? { |card| card["brand"] == "elo" && card["number"].length == 16 && card["formatted"].count(" ") == 3 })
        legacy = get("/api/v1/plate/generate", layout: "legacy", formatted: "true", count: 5, seed: 3).json["items"]
        assert(legacy.all? { |plate| plate.match?(/\A[A-Z]{3}-\d{4}\z/) })
        landline = get("/api/v1/phone/generate", ddd: "61", type: "landline", formatted: "true", count: 5, seed: 3).json["items"]
        assert(landline.all? { |phone| phone.match?(/\A\(61\) [2-5]\d{3}-\d{4}\z/) })
        ceps = get("/api/v1/cep/generate", uf: "DF", count: 10, seed: 3).json["items"]
        assert(ceps.all? { |cep| CEP.uf_for(cep) == "DF" })
      end

      def test_invalid_generator_parameters
        {
          "count=0" => "count", "count=101" => "count", "count=x" => "count", "count=-1" => "count",
          "seed=-1" => "seed", "seed=abc" => "seed", "seed=4294967296" => "seed", "seed=1.5" => "seed",
          "uf=XX" => "uf", "formatted=maybe" => "formatted", "uf=" => "uf"
        }.each do |query, field|
          document = assert_problem(request(app, :get, "/api/v1/cpf/generate", query: query), 400, "invalid-parameter")
          assert_includes document["errors"].map { |error| error["field"] }, field, query
        end
        assert_problem(get("/api/v1/card/generate", brand: "nope"), 400, "invalid-parameter")
        assert_problem(get("/api/v1/phone/generate", ddd: "23"), 400, "invalid-parameter")
        assert_problem(get("/api/v1/phone/generate", type: "satellite"), 400, "invalid-parameter")
        assert_problem(get("/api/v1/plate/generate", layout: "weird"), 400, "invalid-parameter")
        assert_problem(get("/api/v1/cpf/generate", bogus: "1"), 400, "invalid-parameter")
      end

      def test_a_library_level_refusal_is_a_validation_error
        reply = get("/api/v1/cnpj/generate", branch: "ABCD", seed: 1)
        document = assert_problem(reply, 422, "validation-error")
        assert_equal "branch", document["errors"].first["field"]
      end

      # -- fake people -------------------------------------------------------------------------------------

      def test_fake_people
        document = get("/api/v1/fake/person", count: 3, seed: 42).json
        assert_equal ["person", 42, 3], document.values_at("kind", "seed", "count")
        expected = JSON.parse(JSON.generate(Fake.people(3, seed: 42).map(&:to_h)))
        assert_equal expected, document["items"]
        assert_equal "Natália Fernanda Rocha Moura", document["items"].first["name"]
      end

      # -- plates ------------------------------------------------------------------------------------------

      def test_plate_conversion
        document = get("/api/v1/plate/convert", plate: "ABC-1234").json
        assert_equal ["ABC1C34", true], document.values_at("normalized", "valid")
        assert_equal({ "position" => 5, "digit" => "2", "letter" => "C" }, document["details"]["conversion"])
        assert_equal "ABC1D23", get("/api/v1/plate/convert", plate: "abc1d23").json["normalized"]
        refute get("/api/v1/plate/convert", plate: "AB-1").json["valid"]
        assert_problem(get("/api/v1/plate/convert"), 400, "invalid-parameter")
      end

      # -- pix ---------------------------------------------------------------------------------------------

      def test_building_the_manual_payload
        reply = post_json(app, "/api/v1/pix/payload", { key: EVP, name: "Fulano de Tal", city: "BRASILIA" })
        assert_equal 200, reply.status
        document = reply.json
        assert_equal MANUAL_PAYLOAD, document["payload"]
        assert_equal ["1D3D", "evp"], document.values_at("crc", "key_type")
        assert_equal %w[00 26 52 53 58 59 60 62 63], document["fields"].map { |field| field["id"] }
        assert_equal %w[00 01], document["fields"][1]["children"].map { |child| child["id"] }
      end

      def test_building_with_every_field
        reply = post_json(app, "/api/v1/pix/payload", { key: "529.982.247-25", name: "Ação Café Ltda", city: "São Paulo",
                                                       amount: 12.5, txid: "PED123", message: "Pedido 42" })
        expected = "00020126460014br.gov.bcb.pix0111529982247250209Pedido 42520400005303986540512.505802BR5914Acao Cafe " \
                   "Ltda6009Sao Paulo62100506PED1236304E73D"
        assert_equal expected, reply.json["payload"]
        assert_equal "cpf", reply.json["key_type"]
        string_amount = post_json(app, "/api/v1/pix/payload", { key: "a@b.co", name: "N", city: "C", amount: "1,5" })
        assert_includes string_amount.json["payload"], "54041.50"
      end

      def test_the_key_type_can_be_forced
        reply = post_json(app, "/api/v1/pix/payload", { key: "11222333000181", name: "N", city: "C", key_type: "CNPJ" })
        assert_equal "cnpj", reply.json["key_type"]
        assert_problem(post_json(app, "/api/v1/pix/payload", { key: "11222333000181", name: "N", city: "C", key_type: "iban" }),
                       422, "validation-error")
      end

      def test_payload_problems_are_listed_field_by_field
        reply = post_json(app, "/api/v1/pix/payload", { key: "nope", name: "", city: "x" * 20, amount: "0,001",
                                                       txid: "a b", message: "m" * 80 })
        document = assert_problem(reply, 422, "validation-error")
        assert_equal %w[key name city amount txid message], document["errors"].map { |error| error["field"] }
        assert(document["errors"].all? { |error| error["code"] && error["message"] })
        assert_equal "6 fields are invalid", document["detail"]
      end

      def test_payload_body_validation
        unknown = assert_problem(post_json(app, "/api/v1/pix/payload", { key: EVP, name: "N", city: "C", ammount: 1 }), 422,
                                 "validation-error")
        assert_equal [{ "code" => "unknown_field", "message" => unknown["errors"][0]["message"], "field" => "ammount" }],
                     unknown["errors"]
        missing = assert_problem(post_json(app, "/api/v1/pix/payload", {}), 422, "validation-error")
        assert_equal %w[key name city], missing["errors"].map { |error| error["field"] }
        types = assert_problem(post_json(app, "/api/v1/pix/payload", { key: 5, name: true, city: [], amount: {} }), 422,
                               "validation-error")
        assert_equal %w[invalid_type], types["errors"].map { |error| error["code"] }.uniq
      end

      def test_payload_amount_edge_cases
        ["1e400", "-1e400"].each do |literal|
          body = "{\"key\":\"#{EVP}\",\"name\":\"N\",\"city\":\"C\",\"amount\":#{literal}}"
          reply = post_json(app, "/api/v1/pix/payload", body)
          assert_equal "invalid_type", assert_problem(reply, 422, "validation-error")["errors"].first["code"]
        end
        huge = "9" * 400
        reply = post_json(app, "/api/v1/pix/payload", "{\"key\":\"#{EVP}\",\"name\":\"N\",\"city\":\"C\",\"amount\":#{huge}}")
        assert_equal "amount_too_large", assert_problem(reply, 422, "validation-error")["errors"].first["code"]
      end

      def test_payload_content_type_and_method_rules
        no_type = request(app, :post, "/api/v1/pix/payload", body: "{}")
        assert_problem(no_type, 415, "unsupported-media-type")
        wrong = request(app, :post, "/api/v1/pix/payload", body: "{}", headers: { "Content-Type" => "text/plain" })
        assert_problem(wrong, 415, "unsupported-media-type")
        get_reply = get("/api/v1/pix/payload")
        assert_problem(get_reply, 405, "method-not-allowed")
        assert_equal "OPTIONS, POST", get_reply.header("allow")
        assert_problem(post_json(app, "/api/v1/pix/payload", "[]"), 400, "invalid-json")
        assert_problem(post_json(app, "/api/v1/pix/payload", "{nope"), 400, "invalid-json")
        assert_problem(post_json(app, "/api/v1/pix/payload", "", headers: {}), 400, "invalid-json")
      end

      def test_post_endpoints_take_no_query_parameters
        reply = post_json(app, "/api/v1/pix/payload", { key: EVP, name: "N", city: "C" }, query: "debug=1")
        assert_problem(reply, 400, "invalid-parameter")
      end

      def test_decoding_the_manual_payload
        reply = post_json(app, "/api/v1/pix/decode", { payload: MANUAL_PAYLOAD })
        assert_equal 200, reply.status
        document = reply.json
        assert_equal [true, "pix"], document.values_at("valid", "kind")
        assert_equal({ "expected" => "1D3D", "actual" => "1D3D", "valid" => true }, document["details"]["crc"])
        assert_equal EVP, document["details"]["pix"]["key"]
        assert_equal 9, document["details"]["fields"].length
      end

      def test_decoding_can_explain_the_crc
        plain = post_json(app, "/api/v1/pix/decode", { payload: MANUAL_PAYLOAD }).json["details"]["crc"]
        refute plain.key?("steps")

        explained = post_json(app, "/api/v1/pix/decode", { payload: MANUAL_PAYLOAD, explain: true })
        steps = explained.json["details"]["crc"]["steps"]
        assert_equal MANUAL_PAYLOAD.length - 4, steps.length
        assert_equal %w[byte index table crc], steps.first.keys
        assert_equal ["0".ord, 0xFF ^ "0".ord], steps.first.values_at("byte", "index")
        assert_equal 0x1D3D, steps.last["crc"]
        assert_problem(post_json(app, "/api/v1/pix/decode", { payload: MANUAL_PAYLOAD, explain: "yes" }), 422,
                       "validation-error")
      end

      def test_an_invalid_payload_is_still_a_200_with_valid_false
        reply = post_json(app, "/api/v1/pix/decode", { payload: MANUAL_PAYLOAD.sub("Fulano", "Fulana") })
        assert_equal 200, reply.status
        assert_equal false, reply.json["valid"]
        assert_equal ["crc_mismatch"], reply.json["errors"].map { |error| error["code"] }
        garbage = post_json(app, "/api/v1/pix/decode", { payload: "not a pix payload" }).json
        assert_equal ["malformed_tlv"], garbage["errors"].map { |error| error["code"] }
        multiline = post_json(app, "/api/v1/pix/decode", { payload: "000201\n010211" }).json
        assert_equal ["control_characters"], multiline["errors"].map { |error| error["code"] }
      end

      def test_decode_body_validation
        assert_problem(post_json(app, "/api/v1/pix/decode", {}), 422, "validation-error")
        assert_problem(post_json(app, "/api/v1/pix/decode", { payload: 5 }), 422, "validation-error")
        assert_problem(post_json(app, "/api/v1/pix/decode", { payload: "0" * 4097 }), 422, "validation-error")
        assert_problem(post_json(app, "/api/v1/pix/decode", { payload: MANUAL_PAYLOAD, extra: 1 }), 422, "validation-error")
      end

      def test_the_body_size_limit
        reply = request(app, :post, "/api/v1/pix/decode", body: "x" * 20_000, headers: { "Content-Type" => "application/json" })
        assert_problem(reply, 413, "payload-too-large")
        exact = JSON.generate(payload: "0" * (16_384 - 14))
        assert_equal 16_384, exact.bytesize
        refute_equal 413, post_json(app, "/api/v1/pix/decode", exact).status
        assert_equal 413, post_json(app, "/api/v1/pix/decode", "#{exact} ").status
      end

      # -- error documents and protocol ------------------------------------------------------------------------

      def test_problem_documents
        {
          [:get, "/api/v1/nothing"] => [404, "not-found"], [:get, "/api"] => [404, "not-found"],
          [:get, "/api/"] => [404, "not-found"], [:get, "/missing"] => [404, "not-found"],
          [:get, "/api/v1/cpf/validate/"] => [404, "not-found"], [:get, "/API/v1/cpf/validate"] => [404, "not-found"],
          [:post, "/api/v1/cpf/validate"] => [405, "method-not-allowed"],
          [:delete, "/healthz"] => [405, "method-not-allowed"],
          [:put, "/api/v1/pix/payload"] => [405, "method-not-allowed"],
          [:patch, "/api/v1/fake/person"] => [405, "method-not-allowed"],
          [:post, "/index.html"] => [405, "method-not-allowed"]
        }.each do |(verb, path), (status, slug)|
          assert_problem(request(app, verb, path), status, slug)
        end
      end

      def test_method_not_allowed_lists_the_allowed_methods
        assert_equal "GET, HEAD, OPTIONS", request(app, :post, "/healthz").header("allow")
        assert_equal "OPTIONS, POST", request(app, :get, "/api/v1/pix/decode").header("allow")
        assert_equal "GET, HEAD, OPTIONS", request(app, :put, "/does-not-exist").header("allow")
      end

      def test_content_negotiation
        {
          nil => 200, "application/json" => 200, "*/*" => 200, "application/*" => 200, "text/html, */*;q=0.8" => 200,
          "text/html" => 406, "application/xml" => 406, "application/json;q=0" => 406, "text/*" => 406
        }.each do |accept, status|
          headers = accept ? { "Accept" => accept } : {}
          reply = request(app, :get, "/healthz", headers: headers)
          assert_equal status, reply.status, accept.inspect
          assert_problem(reply, 406, "not-acceptable") if status == 406
        end
      end

      def test_head_requests
        get_reply = get("/healthz")
        head_reply = request(app, :head, "/healthz")
        assert_equal 200, head_reply.status
        assert_equal "", head_reply.body
        assert_equal get_reply.header("content-length"), head_reply.header("content-length")
        assert_equal get_reply.header("content-type"), head_reply.header("content-type")
        assert_problem(request(app, :head, "/api/v1/pix/payload"), 405, "method-not-allowed")
        assert_equal 400, request(app, :head, "/api/v1/cpf/validate").status
      end

      def test_options_requests
        reply = request(app, :options, "/healthz")
        assert_equal [204, "GET, HEAD, OPTIONS", ""], [reply.status, reply.header("allow"), reply.body]
        assert_equal "OPTIONS, POST", request(app, :options, "/api/v1/pix/payload").header("allow")
        assert_equal 404, request(app, :options, "/api/v1/nothing").status
      end

      def test_every_response_carries_the_standard_headers
        [[:get, "/healthz"], [:get, "/api/v1/cpf/generate"], [:get, "/api/v1/nothing"], [:post, "/healthz"],
         [:get, "/api/v1/cpf/validate"], [:options, "/healthz"]].each do |verb, path|
          reply = request(app, verb, path)
          assert_match(/\A\h{8}(-\h{4}){3}-\h{12}\z/, reply.header("x-request-id"), "#{verb} #{path}")
          assert_equal "nosniff", reply.header("x-content-type-options")
          assert_equal "no-referrer", reply.header("referrer-policy")
          assert_equal "DENY", reply.header("x-frame-options")
        end
        assert_equal "no-store", get("/healthz").header("cache-control")
      end

      def test_request_ids
        custom = request(app, :get, "/healthz", headers: { "X-Request-Id" => "client-id-12345" })
        assert_equal "client-id-12345", custom.header("x-request-id")
        ["short", "has space in it", "x" * 65, "bad\r\nheader: 1", "semi;colon;colon", "é-not-ascii-id"].each do |value|
          reply = request(app, :get, "/healthz", headers: { "X-Request-Id" => value })
          refute_equal value, reply.header("x-request-id"), value.inspect
          assert_match(/\A\h{8}-/, reply.header("x-request-id"))
        end
        fixed = App.new(config: Config.new(rate_limit_per_minute: 0), public_dir: "/nonexistent",
                        id_generator: -> { "fixed-id-0001" })
        assert_equal "fixed-id-0001", request(fixed, :get, "/healthz").header("x-request-id")
        assert_equal "fixed-id-0001", request(fixed, :get, "/nothing").json["request_id"]
        refute_equal request(app, :get, "/healthz").header("x-request-id"), request(app, :get, "/healthz").header("x-request-id")
      end

      def test_paths_and_queries_with_dangerous_bytes_are_bad_requests
        ["/api/v1/cpf%2Fvalidate", "/api/v1/%00", "/healthz%0D%0Ax", "/%zz", "/api/v1/cpf\\validate"].each do |path|
          assert_problem(request(app, :get, path), 400, "bad-request")
        end
        assert_problem(request(app, :get, "/healthz", query: "x=%0D%0Ainjected"), 400, "bad-request")
      end

      def test_the_app_never_raises
        [{}, { "REQUEST_METHOD" => "GET" }, { "PATH_INFO" => "/healthz" },
         { "REQUEST_METHOD" => "GET", "PATH_INFO" => nil }].each do |env|
          assert_rack_response(app.call(env))
        end
        assert_rack_response(app.call(nil))
        assert_equal 500, app.call(nil).first
        assert_rack_response(app.call({ "REQUEST_METHOD" => "GET", "PATH_INFO" => "/healthz", "QUERY_STRING" => nil }))
      end

      def test_every_route_answers_its_declared_examples
        app.router.routes.each do |route|
          if route.verb == "GET"
            query = URI.encode_www_form(route.params.select { |p| p.required || p.example }.to_h { |p| [p.name, p.example] })
            reply = request(app, :get, route.path, query: query)
          else
            example = route.body.select(&:example).to_h { |field| [field.name, field.example] }
            reply = post_json(app, route.path, example)
          end
          assert_equal 200, reply.status, "#{route.verb} #{route.path}: #{reply.body[0, 200]}"
        end
      end
    end
  end
end
