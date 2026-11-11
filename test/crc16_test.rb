# frozen_string_literal: true

require_relative "test_helper"

module Brkit
  class CRC16Test < Minitest::Test
    # "123456789" => 29B1 is the published check value of CRC-16/CCITT-FALSE. The other vectors were computed with an
    # independent bitwise implementation (Node.js); the library itself is table driven.
    VECTORS = {
      "" => "FFFF",
      "A" => "B915",
      "D" => "E9B0",
      "3De:" => "915E",
      "fD]OMm" => "FF3D",
      "123456789" => "29B1",
      "~hC.o8=" => "A34B",
      "`AnoT'f&XGGYl8%P\"" => "02B9",
      "714&hia\\oWVa6>W`fyJ:R`b" => "0B07"
    }.freeze

    # Static example of the Banco Central "Manual de Padrões para Iniciação do Pix" (CRC printed as 0x1D3D,
    # computed "including 6304").
    PIX_MANUAL_BODY = "00020126580014br.gov.bcb.pix0136123e4567-e12b-12d1-a456-4266554400005204000053039865802BR" \
                      "5913Fulano de Tal6008BRASILIA62070503***6304"

    # Example of section 2.2 of the BR Code manual v2.0.1 (270 characters, CRC printed as 0xAD38).
    BRCODE_MANUAL_BODY = "00020104141234567890123426580014BR.GOV.BCB.PIX0136123e4567-e12b-12d1-a456-4266554400002730" \
                         "0012BR.COM.OUTRO011001234567895204000053039865406123.455802BR5917NOME DO RECEBEDOR6008BRASILIA" \
                         "61087007490062190515RP12345678-201980390012BR.COM.OUTRO01190123.ABCD.3456.WXYZ6304"

    def test_known_vectors
      VECTORS.each do |input, expected|
        assert_equal expected, CRC16.hex(input), "CRC16 of #{input.inspect}"
      end
    end

    def test_pix_manual_static_example_has_crc_1d3d
      assert_equal "1D3D", CRC16.hex(PIX_MANUAL_BODY)
    end

    def test_crc_must_include_the_6304_prefix
      refute_equal "1D3D", CRC16.hex(PIX_MANUAL_BODY.delete_suffix("6304"))
    end

    def test_brcode_manual_example_has_crc_ad38
      assert_equal 270, BRCODE_MANUAL_BODY.length + 4
      assert_equal "AD38", CRC16.hex(BRCODE_MANUAL_BODY)
    end

    def test_checksum_returns_a_16_bit_integer
      assert_equal 0x29B1, CRC16.checksum("123456789")
      assert_equal 0xFFFF, CRC16.checksum("")
    end

    def test_hex_is_zero_padded_uppercase
      assert_equal "02B9", CRC16.hex("`AnoT'f&XGGYl8%P\"")
      assert_match(/\A\h{4}\z/, CRC16.hex("anything"))
      assert_equal CRC16.hex("anything").upcase, CRC16.hex("anything")
    end

    def test_trace_records_one_step_per_byte_and_ends_on_the_checksum
      steps = CRC16.trace("123456789")
      assert_equal 9, steps.length
      assert_equal %w[1 2 3 4 5 6 7 8 9].map(&:ord), steps.map { |step| step[:byte] }
      assert_equal CRC16.checksum("123456789"), steps.last[:crc]
      assert_equal 0x29B1, steps.last[:crc]
    end

    def test_trace_steps_follow_the_table_lookup
      register = CRC16::INITIAL
      CRC16.trace(PIX_MANUAL_BODY).each do |step|
        index = ((register >> 8) ^ step[:byte]) & 0xFF
        assert_equal index, step[:index]
        assert_equal CRC16::TABLE[index], step[:table]
        register = ((register << 8) & 0xFFFF) ^ step[:table]
        assert_equal register, step[:crc]
      end
      assert_equal 0x1D3D, register
    end

    def test_trace_of_nothing_is_empty_and_accepts_an_initial_register
      assert_empty CRC16.trace("")
      assert_equal CRC16.checksum("56789", initial: 0x1234), CRC16.trace("56789", initial: 0x1234).last[:crc]
    end

    def test_trace_works_on_bytes_not_characters
      assert_equal "Ação".bytesize, CRC16.trace("Ação").length
    end

    def test_incremental_computation_matches_one_shot
      assert_equal CRC16.checksum("123456789"), CRC16.checksum("56789", initial: CRC16.checksum("1234"))
    end

    def test_works_on_bytes_regardless_of_encoding
      text = "Ação"
      assert_equal CRC16.checksum(text), CRC16.checksum(text.b)
      refute_equal CRC16.checksum("Acao"), CRC16.checksum(text)
    end

    def test_table_is_frozen_and_complete
      assert_equal 256, CRC16::TABLE.length
      assert_predicate CRC16::TABLE, :frozen?
      assert_equal 0, CRC16::TABLE.first
      assert_equal 0x1021, CRC16::TABLE[1]
    end

    def test_detects_every_single_character_substitution_in_a_pix_payload
      payload = "#{PIX_MANUAL_BODY}1D3D"
      payload.length.times do |index|
        next if index >= payload.length - 4

        tampered = payload.dup
        tampered[index] = tampered[index] == "9" ? "8" : "9"
        refute_equal "1D3D", CRC16.hex(tampered[0...-4]), "substitution at #{index} went unnoticed"
      end
    end
  end
end
