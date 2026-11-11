# frozen_string_literal: true

require_relative "test_helper"

module Brkit
  class PixTLVTest < Minitest::Test
    BCB_SAMPLE = "00020126580014br.gov.bcb.pix0136123e4567-e12b-12d1-a456-4266554400005204000053039865802BR" \
                 "5913Fulano de Tal6008BRASILIA62070503***63041D3D"

    BRCODE_SAMPLE = "00020104141234567890123426580014BR.GOV.BCB.PIX0136123e4567-e12b-12d1-a456-426655440000273000" \
                    "12BR.COM.OUTRO011001234567895204000053039865406123.455802BR5917NOME DO RECEBEDOR6008BRASILIA" \
                    "61087007490062190515RP12345678-201980390012BR.COM.OUTRO01190123.ABCD.3456.WXYZ6304AD38"

    def test_parses_a_simple_field
      field = Pix::TLV.parse("000201").first
      assert_equal ["00", "Payload Format Indicator"], [field.id, field.name]
      assert_equal [2, "01", nil], [field.length, field.value, field.children]
    end

    def test_parses_the_bcb_sample_into_its_root_fields
      fields = Pix::TLV.parse(BCB_SAMPLE)
      assert_equal %w[00 26 52 53 58 59 60 62 63], fields.map(&:id)
      assert_equal [2, 58, 4, 3, 2, 13, 8, 7, 4], fields.map(&:length)
      assert_equal "Fulano de Tal", fields.find { |f| f.id == "59" }.value
    end

    def test_expands_templates_and_names_their_children
      account = Pix::TLV.parse(BCB_SAMPLE).find { |f| f.id == "26" }
      assert_equal %w[00 01], account.children.map(&:id)
      assert_equal ["Globally Unique Identifier", "Pix key (chave)"], account.children.map(&:name)
      assert_equal ["br.gov.bcb.pix", "123e4567-e12b-12d1-a456-426655440000"], account.children.map(&:value)
      additional = Pix::TLV.parse(BCB_SAMPLE).find { |f| f.id == "62" }
      assert_equal "Reference Label (txid)", additional.children.first.name
      assert_equal "***", additional.children.first.value
    end

    def test_round_trips_exactly
      [BCB_SAMPLE, BRCODE_SAMPLE].each do |payload|
        assert_equal payload, Pix::TLV.parse(payload).map(&:encode).join
      end
    end

    def test_parses_the_multi_arrangement_example_of_the_brcode_manual
      fields = Pix::TLV.parse(BRCODE_SAMPLE)
      assert_equal %w[00 04 26 27 52 53 54 58 59 60 61 62 80 63], fields.map(&:id)
      assert_nil fields.find { |f| f.id == "04" }.children, "04 holds a card account number, not a template"
      assert_equal "Unreserved Template", fields.find { |f| f.id == "80" }.name
      assert_equal "12345678901234", fields.find { |f| f.id == "04" }.value
      other = fields.find { |f| f.id == "27" }
      assert_equal ["Globally Unique Identifier", nil], other.children.map(&:name), "only PIX templates get PIX names"
    end

    def test_gui_comparison_is_case_insensitive
      assert Pix::TLV.pix_gui?("br.gov.bcb.pix")
      assert Pix::TLV.pix_gui?("BR.GOV.BCB.PIX")
      refute Pix::TLV.pix_gui?("br.com.outro")
      refute Pix::TLV.pix_gui?(nil)
    end

    def test_template_identifiers
      templates = %w[26 30 51 62 64 80 90 99]
      primitives = %w[00 01 02 25 52 53 58 59 60 61 63 65 79]
      templates.each { |id| assert Pix::TLV.template?(id), id }
      primitives.each { |id| refute Pix::TLV.template?(id), id }
    end

    def test_root_names
      assert_equal "Payload Format Indicator", Pix::TLV.root_name("00")
      assert_equal "Merchant Account Information", Pix::TLV.root_name("03")
      assert_equal "Merchant Account Information", Pix::TLV.root_name("51")
      assert_equal "Reserved for EMVCo", Pix::TLV.root_name("70")
      assert_equal "Unreserved Template", Pix::TLV.root_name("85")
      assert_equal "CRC", Pix::TLV.root_name("63")
      assert_equal "Merchant Name", Pix::TLV.root_name("59")
    end

    def test_child_names
      assert_equal "Pix key (chave)", Pix::TLV.child_name("26", "01", "br.gov.bcb.pix")
      assert_equal "Payload URL", Pix::TLV.child_name("26", "25", "BR.GOV.BCB.PIX")
      assert_equal "Globally Unique Identifier", Pix::TLV.child_name("27", "00", "br.com.outro")
      assert_nil Pix::TLV.child_name("27", "01", "br.com.outro")
      assert_equal "Reference Label (txid)", Pix::TLV.child_name("62", "05", nil)
      assert_equal "Language Preference", Pix::TLV.child_name("64", "00", nil)
      assert_nil Pix::TLV.child_name("62", "99", nil)
    end

    def test_malformed_input_raises_with_a_position
      {
        "00" => 0,
        "0002" => 0,
        "0A0201" => 0,
        "00XX01" => 0,
        "000301" => 0,
        "00020152" => 6,
        "0002015204" => 6,
        "000201520400" => 6,
        "000201-5" => 6
      }.each do |payload, position|
        error = assert_raises(ParseError, payload.inspect) { Pix::TLV.parse(payload) }
        assert_equal position, error.position, payload.inspect
      end
    end

    def test_errors_inside_templates_report_absolute_positions
      error = assert_raises(ParseError) { Pix::TLV.parse("26060014ab") }
      assert_equal 4, error.position
      assert_includes error.message, "declares 14 characters"
      deeper = assert_raises(ParseError) { Pix::TLV.parse("00020126060014ab") }
      assert_equal 10, deeper.position
    end

    def test_empty_text_has_no_fields
      assert_equal [], Pix::TLV.parse("")
    end

    def test_zero_length_fields_are_allowed_by_the_parser
      field = Pix::TLV.parse("5900").first
      assert_equal [0, ""], [field.length, field.value]
    end

    def test_building_fields
      primitive = Pix::TLV.primitive("59", "Ana")
      assert_equal "5903Ana", primitive.encode
      assert_equal "Merchant Name", primitive.name
      template = Pix::TLV.template("62", [Pix::TLV.primitive("05", "***", name: "Reference Label (txid)")])
      assert_equal "62070503***", template.encode
      assert_equal 7, template.length
      assert_equal "05", template.children.first.id
    end

    def test_values_longer_than_99_characters_are_rejected
      assert_equal 99, Pix::TLV.primitive("59", "a" * 99).length
      error = assert_raises(InvalidInputError) { Pix::TLV.primitive("59", "a" * 100) }
      assert_equal [:field_too_long], error.issues.map(&:code)
      children = [Pix::TLV.primitive("00", "a" * 50), Pix::TLV.primitive("01", "b" * 50)]
      assert_raises(InvalidInputError) { Pix::TLV.template("26", children) }
    end

    def test_field_to_h
      hash = Pix::TLV.parse("26250014br.gov.bcb.pix0103abc").first.to_h
      assert_equal %i[id name length value children], hash.keys
      assert_equal 25, hash[:length]
      expected_child = { id: "00", name: "Globally Unique Identifier", length: 14, value: "br.gov.bcb.pix" }
      assert_equal expected_child, hash[:children].first
      assert_equal({ id: "59", name: "Merchant Name", length: 3, value: "Ana" }, Pix::TLV.parse("5903Ana").first.to_h)
    end

    def test_to_h_leaves_out_unknown_names
      child = Pix::TLV.parse("26059901x").first.children.first
      assert_nil child.name
      assert_equal({ id: "99", length: 1, value: "x" }, child.to_h)
    end
  end
end
