# frozen_string_literal: true

require "securerandom"

require_relative "../../brkit"
require_relative "openapi"
require_relative "params"
require_relative "router"

module Brkit
  module API
    # The routes of the API. Each route carries its own parameter declarations, so the same table validates
    # requests and generates the OpenAPI document.
    module Endpoints
      # Most items a single generate request may ask for.
      MAX_COUNT = 100
      # Longest accepted value of a document parameter. Validators report their own "too long" error above 256.
      MAX_VALUE_LENGTH = 512

      COUNT = Params.integer(:count, default: 1, min: 1, max: MAX_COUNT, example: 3,
                                     description: "How many items to generate (1 to #{MAX_COUNT}).")
      SEED = Params.integer(:seed, min: 0, max: Rng::MAX_SEED, example: 42,
                                   description: "Seed of the random generator: the same seed returns the same items. " \
                                                "Omit it for a random one; the seed used is echoed in the response.")
      FORMATTED = Params.boolean(:formatted, default: false, description: "Apply the display mask (dots, dashes, ...).")
      EXPLAIN = Params.boolean(:explain, default: false,
                                         description: "Add the step-by-step checksum computation to details.steps.")
      UF_PARAM = Params.string(:uf, enum: Brkit::UF::CODES, fold: :upcase, example: "SP", max_length: 2,
                                    description: "Two-letter state code.")

      # A document with a validate endpoint.
      Document = Struct.new(:name, :tag, :library, :param, :example, :explain, :about, keyword_init: true)

      DOCUMENTS = [
        Document.new(name: "cpf", tag: "CPF", library: CPF, param: :cpf, example: "529.982.247-25", explain: true,
                     about: "Checks length, repeated digits and both check digits (mod 11); reports the fiscal region."),
        Document.new(name: "cnpj", tag: "CNPJ", library: CNPJ, param: :cnpj, example: "12.ABC.345/01DE-35",
                     explain: true,
                     about: "Classic numeric and the alphanumeric CNPJ in force since July 2026 (letters count as " \
                            "ASCII code minus 48)."),
        Document.new(name: "pis", tag: "PIS", library: PIS, param: :pis, example: "123.45678.91-9", explain: true,
                     about: "PIS, PASEP, NIS and NIT share one 11-digit format with a mod-11 check digit."),
        Document.new(name: "card", tag: "Card", library: Card, param: :number, example: "4111 1111 1111 1111",
                     explain: true,
                     about: "Luhn check and brand detection by leading digits. Use test numbers only."),
        Document.new(name: "plate", tag: "Plate", library: Plate, param: :plate, example: "ABC-1234", explain: false,
                     about: "Legacy AAA-9999 and Mercosul AAA9A99 layouts."),
        Document.new(name: "phone", tag: "Phone", library: Phone, param: :phone, example: "(11) 98765-4321",
                     explain: false,
                     about: "Brazilian geographic numbers: ANATEL area codes, 9-digit mobile and 8-digit landline rules; " \
                            "normalised to E.164."),
        Document.new(name: "cep", tag: "CEP", library: CEP, param: :cep, example: "01310-100", explain: false,
                     about: "Shape check only (8 digits); no address lookup.")
      ].freeze

      class << self
        # Registers every route on +router+.
        #
        # @param router [Router]
        # @return [Router]
        def build(router = Router.new)
          register_meta(router)
          DOCUMENTS.each { |document| register_validator(router, document) }
          register_generators(router)
          register_plate_conversion(router)
          register_pix(router)
          register_fake(router)
          router
        end

        private

        def register_meta(router)
          router.get "/healthz", operation_id: "healthz", tag: "Meta", summary: "Liveness probe",
                                 response: :health do |_context|
            { status: "ok", version: Brkit::VERSION }
          end
          router.get "/api/v1/openapi.json", operation_id: "openapi", tag: "Meta", response: :openapi,
                                             summary: "OpenAPI 3.1 description of this API",
                                             description: "Generated from the route table, so it always matches " \
                                                          "what the server accepts." do |_context|
            OpenAPI.build(router.routes)
          end
        end

        def register_validator(router, document)
          value = Params.string(document.param, required: true, example: document.example,
                                                max_length: MAX_VALUE_LENGTH, description: "The value to check.")
          params = document.explain ? [value, EXPLAIN] : [value]
          router.get "/api/v1/#{document.name}/validate", operation_id: "#{document.name}Validate",
                                                          tag: document.tag, response: :result, params: params,
                                                          summary: "Validate a #{document.tag}",
                                                          description: document.about do |context|
            options = document.explain ? { explain: context.params[:explain] } : {}
            document.library.validate(context.params[document.param], **options).to_h
          end
        end

        def register_generators(router)
          register_identity_generators(router)
          register_contact_generators(router)
          generator(router, "card", "Card", [Params.string(:brand, enum: Card.brands, fold: :downcase, max_length: 16,
                                                                   example: "visa", description: "Card network.")],
                    "Generate Luhn-valid test card numbers with a real brand prefix. They are random: never use them " \
                    "for real payments.") do |params, rng|
            number = Card.generate(brand: params[:brand], rng: rng)
            brand = Card.detect(number)
            { number: number, formatted: Card.group(number, brand), brand: brand.id, brand_name: brand.name }
          end
        end

        def register_identity_generators(router)
          generator(router, "cpf", "CPF", [UF_PARAM, FORMATTED],
                    "Generate checksum-valid CPFs; with uf the fiscal-region digit matches that state.") do |params, rng|
            CPF.generate(uf: params[:uf], formatted: params[:formatted], rng: rng)
          end
          generator(router, "cnpj", "CNPJ",
                    [Params.boolean(:alphanumeric, default: false, description: "Include letters in the root."),
                     Params.string(:branch, default: "0001", max_length: 4, example: "0001",
                                            description: "Four-character branch (ordem); 0001 is the head office."),
                     FORMATTED], "Generate checksum-valid CNPJs, classic numeric or alphanumeric.") do |params, rng|
            CNPJ.generate(alphanumeric: params[:alphanumeric], branch: params[:branch], formatted: params[:formatted],
                          rng: rng)
          end
          generator(router, "pis", "PIS", [FORMATTED], "Generate checksum-valid PIS/PASEP/NIS numbers.") do |params, rng|
            PIS.generate(formatted: params[:formatted], rng: rng)
          end
        end

        def register_contact_generators(router)
          generator(router, "plate", "Plate",
                    [Params.string(:layout, default: "mercosul", enum: %w[mercosul legacy], fold: :downcase,
                                            max_length: 8, description: "Plate layout."), FORMATTED],
                    "Generate plates in the Mercosul (AAA9A99) or legacy (AAA-9999) layout.") do |params, rng|
            Plate.generate(layout: params[:layout], formatted: params[:formatted], rng: rng)
          end
          generator(router, "phone", "Phone", phone_params,
                    "Generate syntactically valid numbers; they may belong to real subscribers.") do |params, rng|
            Phone.generate(ddd: params[:ddd], uf: params[:uf], type: params[:type], formatted: params[:formatted],
                           rng: rng)
          end
          generator(router, "cep", "CEP", [UF_PARAM, FORMATTED],
                    "Generate CEPs whose prefix lies in the state's range (not real addresses).") do |params, rng|
            CEP.generate(uf: params[:uf], formatted: params[:formatted], rng: rng)
          end
        end

        def phone_params
          [Params.string(:ddd, enum: Phone::AREA_CODES.keys, max_length: 2, example: "11",
                               description: "Area code; random when omitted."),
           UF_PARAM,
           Params.string(:type, default: "mobile", enum: %w[mobile landline], fold: :downcase, max_length: 8,
                                description: "Number type."),
           FORMATTED]
        end

        # Registers GET /api/v1/<name>/generate. The block builds one item from the validated parameters and
        # the shared Random; the response echoes the seed so any result can be reproduced.
        def generator(router, name, tag, params, description, &item)
          router.get "/api/v1/#{name}/generate", operation_id: "#{name}Generate", tag: tag, response: :generated,
                                                 params: params + [COUNT, SEED],
                                                 summary: "Generate #{tag} values", description: description do |context|
            seed = context.params[:seed] || SecureRandom.random_number(Rng::MAX_SEED + 1)
            rng = Random.new(seed)
            items = Array.new(context.params[:count]) { item.call(context.params, rng) }
            { kind: name, seed: seed, count: items.length, items: items }
          end
        end

        def register_plate_conversion(router)
          plate = Params.string(:plate, required: true, example: "ABC-1234", max_length: MAX_VALUE_LENGTH,
                                        description: "A legacy or Mercosul plate.")
          router.get "/api/v1/plate/convert", operation_id: "plateConvert", tag: "Plate", response: :result,
                                              params: [plate], summary: "Convert a legacy plate to Mercosul",
                                              description: "The 5th character becomes a letter: 0 to A, 1 to B, ... " \
                                                           "9 to J. Mercosul plates are returned unchanged." do |context|
            Plate.convert(context.params[:plate]).to_h
          end
        end

        def register_pix(router)
          router.post "/api/v1/pix/payload", operation_id: "pixPayload", tag: "PIX", response: :pix_payload,
                                             body: pix_payload_fields, summary: "Build a static PIX payload (BR Code)",
                                             description: "Returns the copia-e-cola text, its CRC and the TLV tree. " \
                                                          "Render the payload with any QR encoder." do |context|
            Pix.build(**context.body).to_h
          end
          payload = Params.string(:payload, required: true, max_length: 4_096, example: PIX_EXAMPLE,
                                            description: "A BR Code payload (copia e cola).")
          explain = Params.boolean(:explain, default: false,
                                             description: "Add the CRC register after every byte to details.crc.steps.")
          router.post "/api/v1/pix/decode", operation_id: "pixDecode", tag: "PIX", response: :result,
                                            body: [payload, explain], summary: "Decode and check a PIX payload",
                                            description: "Parses the TLV tree and validates structure and CRC. An " \
                                                         "invalid payload still answers 200 with valid: false." do |context|
            Pix.decode(context.body[:payload], explain: context.body[:explain]).to_h
          end
        end

        def pix_payload_fields
          [
            Params.string(:key, required: true, max_length: 100, example: "123e4567-e12b-12d1-a456-426655440000",
                                description: "PIX key: CPF, CNPJ, mobile phone, e-mail or random key."),
            Params.string(:name, required: true, max_length: 200, example: "Fulano de Tal",
                                 description: "Merchant name; at most 25 characters once accents are removed."),
            Params.string(:city, required: true, max_length: 200, example: "BRASILIA",
                                 description: "Merchant city; at most 15 characters once accents are removed."),
            Params.decimal(:amount, max_length: 32, example: 12.5,
                                    description: "Value in reais with at most two decimals; omit for an open amount."),
            Params.string(:txid, max_length: 100, example: "PED123",
                                 description: "Reconciliation id, 1 to 25 letters or digits."),
            Params.string(:message, max_length: 300, example: "Pedido 42",
                                    description: "Text shown to the payer; shares 99 characters with the key."),
            Params.string(:key_type, enum: Pix::Key::TYPES, fold: :downcase, max_length: 8,
                                     description: "Force the key type instead of detecting it.")
          ]
        end

        def register_fake(router)
          router.get "/api/v1/fake/person", operation_id: "fakePerson", tag: "Fake", response: :people,
                                            params: [COUNT, SEED], summary: "Generate fictitious people",
                                            description: "Names, a checksum-valid CPF, e-mail on a reserved example " \
                                                         "domain, phone, birthdate and address. Synthetic data " \
                                                         "that is reproducible from a seed." do |context|
            seed = context.params[:seed] || SecureRandom.random_number(Rng::MAX_SEED + 1)
            people = Fake.people(context.params[:count], seed: seed)
            { kind: "person", seed: seed, count: people.length, items: people.map(&:to_h) }
          end
        end
      end

      # The static example of the Banco Central Pix manual, used in documentation.
      PIX_EXAMPLE = "00020126580014br.gov.bcb.pix0136123e4567-e12b-12d1-a456-4266554400005204000053039865802BR5913" \
                    "Fulano de Tal6008BRASILIA62070503***63041D3D"
    end
  end
end
