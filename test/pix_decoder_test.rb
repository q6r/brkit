# frozen_string_literal: true

require_relative "test_helper"

module Brkit
  class PixDecoderTest < Minitest::Test
    MANUAL_PAYLOAD = "00020126580014br.gov.bcb.pix0136123e4567-e12b-12d1-a456-4266554400005204000053039865802BR5913" \
                     "Fulano de Tal6008BRASILIA62070503***63041D3D"

    # Section 2.2 of the BR Code manual v2.0.1: three arrangements in one code, 270 characters, CRC 0xAD38.
    BRCODE_PAYLOAD = "00020104141234567890123426580014BR.GOV.BCB.PIX0136123e4567-e12b-12d1-a456-4266554400002730" \
                     "0012BR.COM.OUTRO011001234567895204000053039865406123.455802BR5917NOME DO RECEBEDOR6008BRASILIA" \
                     "61087007490062190515RP12345678-201980390012BR.COM.OUTRO01190123.ABCD.3456.WXYZ6304AD38"

    EVP = "123e4567-e12b-12d1-a456-426655440000"
    BASE = [
      ["00", "01"], ["26", "0014br.gov.bcb.pix0136#{EVP}"], ["52", "0000"], ["53", "986"], ["58", "BR"],
      ["59", "Fulano de Tal"], ["60", "BRASILIA"], ["62", "0503***"]
    ].freeze

    # Assembles a payload from [id, value] pairs with a correct CRC, so a test can break exactly one thing.
    def payload_from(fields)
      body = fields.map { |id, value| "#{id}#{value.length.to_s.rjust(2, '0')}#{value}" }.join
      "#{body}6304#{CRC16.hex("#{body}6304")}"
    end

    def decode_fields(fields)
      Pix.decode(payload_from(fields))
    end

    # BASE with the value of one field replaced.
    def base_with(id, value)
      BASE.map { |field_id, field_value| field_id == id ? [id, value] : [field_id, field_value] }
    end

    def base_without(*ids)
      BASE.reject { |id, _value| ids.include?(id) }
    end

    def test_the_manual_examples_are_valid
      [MANUAL_PAYLOAD, BRCODE_PAYLOAD].each do |payload|
        result = Pix.decode(payload)
        assert_valid result, result.error_messages.inspect
        assert_equal payload, result.normalized
        assert_equal payload.length, result.details[:length]
      end
      assert_equal({ expected: "1D3D", actual: "1D3D", valid: true }, Pix.decode(MANUAL_PAYLOAD).details[:crc])
      assert_equal({ expected: "AD38", actual: "AD38", valid: true }, Pix.decode(BRCODE_PAYLOAD).details[:crc])
    end

    def test_decodes_the_tree
      fields = Pix.decode(MANUAL_PAYLOAD).details[:fields]
      assert_equal %w[00 26 52 53 58 59 60 62 63], fields.map { |f| f[:id] }
      assert_equal ["Merchant Account Information", 58], fields[1].values_at(:name, :length)
      assert_equal %w[00 01], fields[1][:children].map { |c| c[:id] }
      assert_equal "Fulano de Tal", fields[5][:value]
    end

    def test_summarises_the_pix_template
      expected = { template: "26", key: EVP, key_type: "evp", message: nil, url: nil, fss: nil, dynamic: false,
                   single_use: false, amount: nil, merchant_name: "Fulano de Tal", merchant_city: "BRASILIA",
                   txid: "***" }
      assert_equal expected, Pix.decode(MANUAL_PAYLOAD).details[:pix]
    end

    def test_the_brcode_manual_example_has_a_pix_template_among_other_arrangements
      pix = Pix.decode(BRCODE_PAYLOAD).details[:pix]
      assert_equal "26", pix[:template]
      assert_equal [EVP, "123.45", "NOME DO RECEBEDOR", "RP12345678-2019"],
                   pix.values_at(:key, :amount, :merchant_name, :txid)
    end

    def test_a_payload_without_a_pix_template_has_no_summary
      result = decode_fields(base_with("26", "0012BR.COM.OUTRO0105abcde"))
      assert_valid result, result.error_messages.inspect
      assert_nil result.details[:pix]
    end

    def test_dynamic_payloads_carry_a_url_instead_of_a_key
      url = "pix.example.com/qr1"
      template = "0014br.gov.bcb.pix25#{url.length.to_s.rjust(2, '0')}#{url}"
      result = decode_fields(base_with("26", template) + [["01", "12"]])
      assert_valid result, result.error_messages.inspect
      pix = result.details[:pix]
      assert_equal [url, true, true], pix.values_at(:url, :dynamic, :single_use)
      assert_nil pix[:key]
    end

    def test_a_pix_template_needs_a_key_or_a_url
      result = decode_fields(base_with("26", "0014br.gov.bcb.pix0203abc"))
      assert_equal [:missing_pix_key], result.errors.map(&:code)
      assert_equal ["26"], result.errors.map(&:field)
    end

    def test_lower_case_crc_digits_are_accepted
      assert_valid Pix.decode(MANUAL_PAYLOAD.sub("1D3D", "1d3d"))
    end

    def test_surrounding_whitespace_is_ignored
      assert_valid Pix.decode("  #{MANUAL_PAYLOAD}\n")
      assert_equal MANUAL_PAYLOAD, Pix.decode("\t#{MANUAL_PAYLOAD} ").normalized
    end

    def test_text_level_problems
      assert_equal [:blank], Pix.decode("").errors.map(&:code)
      assert_equal [:blank], Pix.decode("   \n").errors.map(&:code)
      assert_equal [:blank], Pix.decode(nil).errors.map(&:code)
      with_newline = "#{MANUAL_PAYLOAD[0, 30]}\n#{MANUAL_PAYLOAD[30..]}"
      assert_equal [:control_characters], Pix.decode(with_newline).errors.map(&:code)
      with_nul = MANUAL_PAYLOAD.sub("Fulano", "Ful\u0000ano")
      assert_equal [:control_characters], Pix.decode(with_nul).errors.map(&:code)
      assert_equal [:too_long], Pix.decode("0" * 2049).errors.map(&:code)
      refute_equal [:too_long], Pix.decode("0" * 2048).errors.map(&:code)
    end

    def test_malformed_tlv_reports_where
      result = Pix.decode("000201260")
      assert_equal [:malformed_tlv], result.errors.map(&:code)
      assert_equal 6, result.details[:position]
      refute result.details.key?(:fields)
      assert_nil Pix.decode("hello world").details[:crc]
    end

    def test_crc_mismatch
      result = Pix.decode(MANUAL_PAYLOAD.sub("Fulano", "Fulana"))
      assert_equal [:crc_mismatch], result.errors.map(&:code)
      assert_equal %w[1D3D 5669], result.details[:crc].values_at(:actual, :expected)
      refute result.details[:crc][:valid]
      assert_equal "63", result.errors.first.field
      assert_includes result.errors.first.message, "1D3D"
      assert_includes result.errors.first.message, "5669"
    end

    def test_every_single_character_change_is_detected
      [MANUAL_PAYLOAD, BRCODE_PAYLOAD].each do |payload|
        payload.length.times do |index|
          mutated = payload.dup
          mutated[index] = mutated[index] == "7" ? "3" : "7"
          refute_valid Pix.decode(mutated), "change at #{index} went unnoticed in #{payload[0, 20]}..."
        end
      end
    end

    def test_every_truncation_is_rejected_without_raising
      [MANUAL_PAYLOAD, BRCODE_PAYLOAD].each do |payload|
        (0...payload.length).each do |length|
          refute_valid Pix.decode(payload[0, length]), "truncated to #{length} characters"
        end
      end
    end

    def test_garbage_never_raises
      random = Random.new(21)
      alphabet = [*"0".."9", *"A".."Z", "*", " ", ".", "-", "é", "\u0000"]
      500.times do
        text = Array.new(random.rand(0..60)) { alphabet[random.rand(alphabet.length)] }.join
        assert_kind_of Result, Pix.decode(text)
      end
      assert_kind_of Result, Pix.decode("\xFF\xFE0002")
    end

    def test_mutated_payloads_never_raise
      random = Random.new(5)
      500.times do
        payload = [MANUAL_PAYLOAD, BRCODE_PAYLOAD].sample(random: random).dup
        case random.rand(3)
        when 0 then payload[random.rand(payload.length)] = random.rand(10).to_s
        when 1 then payload.slice!(random.rand(payload.length), random.rand(1..5))
        else payload.insert(random.rand(payload.length), random.rand(100).to_s)
        end
        assert_kind_of Result, Pix.decode(payload)
      end
    end

    def test_the_payload_must_start_with_the_format_indicator
      assert_error decode_fields(base_without("00") + [["00", "01"]]), :bad_format_indicator
      assert_error decode_fields(base_with("00", "02")), :bad_format_indicator
      assert_error decode_fields([["01", "11"]] + BASE), :bad_format_indicator
    end

    def test_the_payload_must_end_with_the_crc_field
      assert_error Pix.decode(MANUAL_PAYLOAD[0...-8]), :missing_crc
      # field 65 follows the CRC field (IDs 65-79 are plain values, not templates)
      assert_error Pix.decode("#{MANUAL_PAYLOAD}6501X"), :missing_crc
      assert_nil Pix.decode("#{MANUAL_PAYLOAD}6501X").details[:crc]
    end

    def test_duplicate_root_fields
      result = decode_fields(BASE + [["59", "Fulano de Tal"]])
      assert_equal [:duplicate_field], result.errors.map(&:code)
      assert_equal ["59"], result.errors.map(&:field)
    end

    def test_missing_mandatory_fields
      { "52" => "Merchant Category Code", "53" => "Transaction Currency", "58" => "Country Code",
        "59" => "Merchant Name", "60" => "Merchant City", "62" => "Additional Data Field Template" }.each do |id, name|
        result = decode_fields(base_without(id))
        assert_equal [:missing_field], result.errors.map(&:code), "without #{id}"
        assert_equal [id], result.errors.map(&:field)
        assert_includes result.errors.first.message, name
      end
    end

    def test_a_merchant_account_template_is_required
      result = decode_fields(base_without("26"))
      assert_equal [:missing_field], result.errors.map(&:code)
      assert_includes result.errors.first.message, "merchant account"
    end

    def test_fixed_values
      result = decode_fields(base_with("53", "840"))
      assert_equal [:unexpected_value], result.errors.map(&:code)
      assert_equal ["53"], result.errors.map(&:field)
      assert_includes result.errors.first.message, "986"
      assert_equal ["58"], decode_fields(base_with("58", "US")).errors.map(&:field)
    end

    def test_name_and_city_length_limits
      assert_valid decode_fields(base_with("59", "N" * 25))
      long_name = decode_fields(base_with("59", "N" * 26))
      assert_equal [:field_length], long_name.errors.map(&:code)
      assert_equal ["59"], long_name.errors.map(&:field)
      assert_valid decode_fields(base_with("60", "C" * 15))
      assert_equal ["60"], decode_fields(base_with("60", "C" * 16)).errors.map(&:field)
      assert_equal [:field_length], decode_fields(base_with("59", "")).errors.map(&:code)
    end

    def test_amount_syntax
      ["12.50", "0", "1.00", "123.99", "1000000"].each do |amount|
        assert_valid decode_fields(BASE + [["54", amount]]), amount
      end
      ["12,50", "-1", "1e3", "abc", "1.", ".5", "1 2"].each do |amount|
        result = decode_fields(BASE + [["54", amount]])
        assert_equal [:invalid_amount], result.errors.map(&:code), amount
      end
    end

    def test_reference_label_rules
      result = decode_fields(base_with("62", "0103abc"))
      assert_equal [:missing_field], result.errors.map(&:code)
      assert_equal ["62"], result.errors.map(&:field)
      assert_valid decode_fields(base_with("62", "0525#{'a' * 25}"))
      long = decode_fields(base_with("62", "0526#{'a' * 26}"))
      assert_equal [:field_length], long.errors.map(&:code)
    end

    def test_several_problems_are_reported_together
      fields = base_without("52", "58").map { |id, value| id == "53" ? ["53", "840"] : [id, value] }
      assert_equal %w[52 53 58], decode_fields(fields).errors.map(&:field).sort
    end

    def test_explain_adds_the_crc_steps_only_when_asked
      plain = Pix.decode(MANUAL_PAYLOAD).details[:crc]
      refute plain.key?(:steps)

      crc = Pix.decode(MANUAL_PAYLOAD, explain: true).details[:crc]
      assert_equal MANUAL_PAYLOAD.length - 4, crc[:steps].length
      assert_equal 0x1D3D, crc[:steps].last[:crc]
      assert_equal plain, crc.except(:steps)
    end

    def test_explain_steps_cover_the_body_even_when_the_crc_is_wrong
      tampered = MANUAL_PAYLOAD.sub("Fulano", "Fulana")
      crc = Pix.decode(tampered, explain: true).details[:crc]
      refute crc[:valid]
      assert_equal CRC16.checksum(tampered[0...-4]), crc[:steps].last[:crc]
      assert_equal crc[:expected], format("%04X", crc[:steps].last[:crc])
    end

    def test_explain_without_a_crc_field_has_nothing_to_show
      result = Pix.decode(payload_from(BASE).sub(/6304\h{4}\z/, ""), explain: true)
      assert_nil result.details[:crc]
    end

    def test_json_round_trip
      parsed = JSON.parse(JSON.generate(Pix.decode(MANUAL_PAYLOAD)))
      assert_equal "pix", parsed["kind"]
      assert_equal true, parsed["valid"]
      assert_equal "26", parsed["details"]["fields"][1]["id"]
      assert_equal EVP, parsed["details"]["pix"]["key"]
    end

    def test_valid_predicate
      assert Pix.valid?(MANUAL_PAYLOAD)
      refute Pix.valid?("nope")
    end

    def test_the_decoder_does_not_mutate_its_input
      payload = MANUAL_PAYLOAD.dup
      Pix.decode(payload)
      assert_equal MANUAL_PAYLOAD, payload
    end
  end
end
