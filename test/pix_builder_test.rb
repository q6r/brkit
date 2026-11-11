# frozen_string_literal: true

require_relative "test_helper"

module Brkit
  class PixBuilderTest < Minitest::Test
    EVP = "123e4567-e12b-12d1-a456-426655440000"

    # The static example printed in the Banco Central "Manual de Padrões para Iniciação do Pix" (section 2.6.3).
    MANUAL_PAYLOAD = "00020126580014br.gov.bcb.pix0136123e4567-e12b-12d1-a456-4266554400005204000053039865802BR5913" \
                     "Fulano de Tal6008BRASILIA62070503***63041D3D"

    # Payloads assembled by an independent implementation (Node.js, plain TLV concatenation + bitwise CRC).
    ORACLE = {
      cpf_full: ["00020126460014br.gov.bcb.pix0111529982247250209Pedido 42520400005303986540512.505802BR5914Acao Cafe " \
                 "Ltda6009Sao Paulo62100506PED1236304E73D",
                 { key: "529.982.247-25", name: "Ação Café Ltda", city: "São Paulo", amount: 12.5, txid: "PED123",
                   message: "Pedido 42" }],
      phone_minimal: ["00020126360014br.gov.bcb.pix0114+55619123456785204000053039865802BR5911Maria Silva6008Brasilia" \
                      "62070503***6304B126",
                      { key: "(61) 91234-5678", name: "Maria Silva", city: "Brasilia" }],
      email_amount: ["00020126590014br.gov.bcb.pix0137fulano_da_silva.recebedor@example.com52040000530398654071000.00" \
                     "5802BR5904Loja6006Recife62060502A16304C50D",
                     { key: "fulano_da_silva.recebedor@example.com", name: "Loja", city: "Recife", amount: 1000,
                       txid: "A1" }],
      cnpj_message: ["00020126480014br.gov.bcb.pix011412ABC34501DE350208obrigado52040000530398654040.015802BR5909" \
                     "Empresa X6008Curitiba62070503***63042A5F",
                     { key: "12.ABC.345/01DE-35", name: "Empresa X", city: "Curitiba", amount: "0,01",
                       message: "obrigado" }]
    }.freeze

    def build(**overrides)
      Pix.build(key: EVP, name: "Fulano de Tal", city: "BRASILIA", **overrides)
    end

    def issues_for(**overrides)
      error = assert_raises(InvalidInputError) { build(**overrides) }
      error.issues
    end

    def test_reproduces_the_manual_example_byte_for_byte
      payload = build
      assert_equal MANUAL_PAYLOAD, payload.to_s
      assert_equal "1D3D", payload.crc
      assert_equal "evp", payload.key_type
      assert_equal MANUAL_PAYLOAD, payload.payload
    end

    def test_matches_payloads_assembled_independently
      ORACLE.each do |name, (expected, inputs)|
        assert_equal expected, Pix.build(**inputs).to_s, name.to_s
      end
    end

    def test_built_payloads_decode_back_to_their_inputs
      ORACLE.each_value do |(expected, _inputs)|
        result = Pix.decode(expected)
        assert_valid result, result.error_messages.inspect
      end
      pix = Pix.decode(build(amount: "12.50", txid: "ABC123", message: "hello").to_s).details[:pix]
      assert_equal({ key: EVP, key_type: "evp", message: "hello", amount: "12.50", txid: "ABC123",
                     merchant_name: "Fulano de Tal", merchant_city: "BRASILIA" },
                   pix.slice(:key, :key_type, :message, :amount, :txid, :merchant_name, :merchant_city))
    end

    def test_fields_are_the_parsed_payload
      payload = build(amount: 5, message: "oi")
      assert_equal Pix::TLV.parse(payload.to_s).map(&:to_h), payload.fields.map(&:to_h)
      assert_equal %w[00 26 52 53 54 58 59 60 62 63], payload.fields.map(&:id)
      assert_equal payload.crc, payload.fields.last.value
    end

    def test_to_h_is_json_friendly
      parsed = JSON.parse(JSON.generate(build.to_h))
      assert_equal %w[payload crc key_type fields], parsed.keys
      assert_equal "1D3D", parsed["crc"]
      assert_equal "26", parsed["fields"][1]["id"]
      assert_equal "br.gov.bcb.pix", parsed["fields"][1]["children"][0]["value"]
    end

    def test_key_forms_are_normalised
      assert_includes build(key: "529.982.247-25").to_s, "011152998224725"
      assert_includes build(key: "11.222.333/0001-81").to_s, "011411222333000181"
      assert_includes build(key: "FULANO@EXAMPLE.COM").to_s, "fulano@example.com"
      assert_includes build(key: "(61) 91234-5678").to_s, "+5561912345678"
      assert_equal "cnpj", build(key: "12abc34501de35").key_type
    end

    def test_key_type_can_be_forced
      assert_equal "cnpj", build(key: "11222333000181", key_type: :cnpj).key_type
      assert_equal %w[key], issues_for(key: "11222333000181", key_type: :cpf).map(&:field).uniq
    end

    AMOUNTS = {
      12.5 => "12.50", 12 => "12.00", "12" => "12.00", "12.5" => "12.50", "12,5" => "12.50", "12,50" => "12.50",
      "0.01" => "0.01", "0,01" => "0.01", 0.01 => "0.01", 1000 => "1000.00", " 12.50 " => "12.50",
      "012.50" => "12.50", "9999999999.99" => "9999999999.99", 1.0 => "1.00", "5.1" => "5.10"
    }.freeze

    def test_amount_formats
      AMOUNTS.each do |input, expected|
        payload = build(amount: input)
        assert_includes payload.to_s, "54#{expected.length.to_s.rjust(2, '0')}#{expected}", input.inspect
        assert_equal expected, Pix.decode(payload.to_s).details[:pix][:amount], input.inspect
      end
    end

    def test_absent_amounts_leave_out_field_54
      [nil, "", "  "].each do |blank|
        refute_includes build(amount: blank).fields.map(&:id), "54", blank.inspect
      end
    end

    def test_rejected_amounts
      ["0", "0.00", 0, 0.0, "-1", -5, "12.345", "1e3", "abc", "1.234,56", "10000000000.00", 10**12, Float::NAN,
       Float::INFINITY, 0.1 + 0.2, true, [], {}, "1,2,3", "12.", ".5"].each do |amount|
        issues = issues_for(amount: amount)
        assert_equal %w[amount], issues.map(&:field), "amount #{amount.inspect}"
      end
    end

    def test_amount_error_codes
      assert_equal [:invalid_amount], issues_for(amount: "12.345").map(&:code)
      assert_equal [:invalid_amount], issues_for(amount: 0).map(&:code)
      assert_equal [:amount_too_large], issues_for(amount: "10000000000").map(&:code)
    end

    def test_txid
      assert_includes build(txid: "PED123").to_s, "62100506PED123"
      assert_includes build(txid: nil).to_s, "62070503***"
      assert_includes build(txid: "").to_s, "62070503***"
      assert_includes build(txid: "***").to_s, "62070503***"
      assert_includes build(txid: "a" * 25).to_s, "62290525#{'a' * 25}"
      assert_includes build(txid: " X1 ").to_s, "0502X1"
    end

    def test_rejected_txids
      ["a" * 26, "a b", "ped-1", "pedido_1", "ção", "***1", "*"].each do |txid|
        assert_equal [:invalid_txid], issues_for(txid: txid).map(&:code), txid.inspect
      end
    end

    def test_name_and_city_limits
      assert_equal 25, Pix.decode(build(name: "A" * 25).to_s).details[:pix][:merchant_name].length
      assert_equal 15, Pix.decode(build(city: "B" * 15).to_s).details[:pix][:merchant_city].length
      name_issue = issues_for(name: "A" * 26).first
      assert_equal [:too_long, "name"], [name_issue.code, name_issue.field]
      assert_includes name_issue.message, "at most 25"
      city_issue = issues_for(city: "B" * 16).first
      assert_equal [:too_long, "city"], [city_issue.code, city_issue.field]
    end

    def test_text_is_normalised
      assert_includes build(name: "Ação Café", city: "São Paulo").to_s, "5909Acao Cafe6009Sao Paulo"
      assert_includes build(name: "  Fulano   de\tTal \n").to_s, "5913Fulano de Tal"
      assert_includes build(name: "ÀÉÎÕÜÇ").to_s, "5906AEIOUC"
    end

    def test_accents_are_folded_before_the_length_check
      assert_equal "A" * 25, Pix.decode(build(name: "Á" * 25).to_s).details[:pix][:merchant_name]
    end

    def test_unsupported_characters_are_rejected
      ["Zoë ☃", "名前", "emoji \u{1F600}", "a\u0000b", "tab\u0007"].each do |name|
        assert_equal [:invalid_characters], issues_for(name: name).map(&:code), name.inspect
      end
    end

    def test_required_fields
      issues = issues_for(name: nil, city: " ", key: "")
      assert_equal([%w[key blank], %w[name missing], %w[city missing]], issues.map { |i| [i.field, i.code.to_s] })
      assert_equal %w[name], issues_for(name: "").map(&:field)
    end

    def test_every_problem_is_reported_at_once
      issues = issues_for(key: "nope", name: "", city: "x" * 20, amount: "0,001", txid: "a b", message: "m" * 80)
      assert_equal %w[key name city amount txid message], issues.map(&:field)
    end

    def test_message
      payload = build(message: "Obrigado pela compra")
      assert_includes payload.to_s, "0220Obrigado pela compra"
      assert_equal "Obrigado pela compra", Pix.decode(payload.to_s).details[:pix][:message]
      assert_equal %w[00 01 02], payload.fields.find { |f| f.id == "26" }.children.map(&:id)
      refute_includes build(message: nil).fields.find { |f| f.id == "26" }.children.map(&:id), "02"
      refute_includes build(message: "  ").fields.find { |f| f.id == "26" }.children.map(&:id), "02"
    end

    def test_message_and_key_share_99_characters
      # 99 - GUI (18) - key field (4 + key) - message header (4)
      room = { EVP => 37, "529.982.247-25" => 62, "11.222.333/0001-81" => 59, "+5561912345678" => 59 }
      room.each do |key, free|
        assert_equal 99 - 18 - 4 - Pix::Key.parse(key).normalized.length - 4, free, key
        assert_equal 99, build(key: key, message: "m" * free).fields[1].length, "message of #{free} characters"
        issue = issues_for(key: key, message: "m" * (free + 1)).first
        assert_equal [:template_too_long, "message"], [issue.code, issue.field], key
        assert_includes issue.message, "at most #{free}"
      end
    end

    def test_message_longer_than_the_72_character_field_limit_is_rejected
      issue = issues_for(message: "m" * 73).first
      assert_equal [:too_long, "message"], [issue.code, issue.field]
      assert_includes issue.message, "at most 72"
    end

    def test_longest_possible_email_key_leaves_no_room_for_a_message
      key = "#{'x' * 64}@#{'d' * 8}.com"
      assert_equal 99, build(key: key).fields[1].length
      issue = issues_for(key: key, message: "m").first
      assert_equal :template_too_long, issue.code
      assert_includes issue.message, "at most 0"
    end

    def test_built_payloads_stay_decodable_for_random_inputs
      random = Random.new(7)
      100.times do |index|
        person = Fake.person(rng: random)
        key = [CPF.generate(rng: random), CNPJ.generate(rng: random), person.email, person.phone_e164,
               "#{index.to_s.rjust(8, '0')}-e12b-12d1-a456-426655440000"][index % 5]
        payload = Pix.build(key: key, name: person.name[0, 25], city: person.address[:city][0, 15],
                            amount: index.even? ? "#{random.rand(1..99_999)}.#{random.rand(10..99)}" : nil,
                            txid: (index % 3).zero? ? "TX#{index}" : nil, message: (index % 4).zero? ? "ref #{index}" : nil)
        result = Pix.decode(payload.to_s)
        assert_valid result, "#{payload}: #{result.error_messages.inspect}"
        assert_equal payload.crc, result.details[:crc][:actual]
      end
    end
  end
end
