# frozen_string_literal: true

require_relative "test_helper"

module Brkit
  class PixKeyTest < Minitest::Test
    # input => [type, value written in the payload]. The first group is the table of key formats in the
    # Banco Central Pix manual (e-mail, CNPJ, mobile number and random key; its CPF example 12345678900 has an
    # invalid check digit, so it is tested separately).
    VALID = {
      "fulano_da_silva.recebedor@example.com" => ["email", "fulano_da_silva.recebedor@example.com"],
      "00038166000105" => %w[cnpj 00038166000105],
      "12ABC34501DE35" => %w[cnpj 12ABC34501DE35],
      "+5561912345678" => %w[phone +5561912345678],
      "123e4567-e12b-12d1-a456-426655440000" => ["evp", "123e4567-e12b-12d1-a456-426655440000"],
      "529.982.247-25" => %w[cpf 52998224725],
      "52998224725" => %w[cpf 52998224725],
      " 529.982.247-25 " => %w[cpf 52998224725],
      "11.222.333/0001-81" => %w[cnpj 11222333000181],
      "12.abc.345/01de-35" => %w[cnpj 12ABC34501DE35],
      "(61) 91234-5678" => %w[phone +5561912345678],
      "61 91234-5678" => %w[phone +5561912345678],
      "+55 61 91234-5678" => %w[phone +5561912345678],
      "Fulano.Silva@Example.COM" => ["email", "fulano.silva@example.com"],
      "123E4567-E12B-12D1-A456-426655440000" => ["evp", "123e4567-e12b-12d1-a456-426655440000"]
    }.freeze

    def test_valid_keys
      VALID.each do |input, (type, value)|
        result = Pix::Key.parse(input)
        assert_valid result, "#{input.inspect}: #{result.error_messages.inspect}"
        assert_equal type, result.details[:type], input
        assert_equal value, result.normalized, input
      end
    end

    def test_the_manual_cpf_example_has_an_invalid_check_digit
      result = Pix::Key.parse("12345678900")
      refute_valid result
      assert_equal "cpf", result.details[:type]
      assert_error result, :checksum
      assert_nil result.normalized
    end

    def test_invalid_keys
      {
        "" => :blank,
        "   " => :blank,
        "hello" => :unrecognised_key,
        "12345" => :unrecognised_key,
        "529.982.247-26" => :checksum,
        "11.222.333/0001-82" => :checksum,
        "no-at-sign@" => :invalid_email,
        "a@b" => :invalid_email,
        "a@@b.com" => :invalid_email,
        "a b@example.com" => :invalid_email,
        "@example.com" => :invalid_email,
        "user@exa_mple.com" => :invalid_email,
        "123e4567-e12b-12d1-a456-42665544000" => :unrecognised_key,
        "+5511" => :invalid_length,
        "+1 202 555 0100" => :foreign_number,
        "+551134567890" => :not_mobile,
        "(11) 3456-7890" => :not_mobile
      }.each do |input, code|
        result = Pix::Key.parse(input)
        refute_valid result, input.inspect
        assert_error result, code, "#{input.inspect} => #{result.error_messages.inspect}"
      end
    end

    def test_a_bare_eleven_digit_number_is_a_cpf_and_the_error_suggests_the_phone_format
      result = Pix::Key.parse("61912345678")
      refute_valid result
      assert_equal "cpf", result.details[:type]
      assert_includes result.error_messages.join, "+5561912345678"
    end

    def test_email_length_limit
      local = "x" * 64
      assert_valid Pix::Key.parse("#{local}@#{'d' * 8}.com")
      assert_equal 77, "#{local}@#{'d' * 8}.com".length
      too_long = Pix::Key.parse("#{local}@#{'d' * 9}.com")
      assert_error too_long, :too_long
      assert_error Pix::Key.parse("#{'x' * 65}@d.com"), :invalid_email
    end

    def test_forcing_the_type
      assert_equal "cnpj", Pix::Key.parse("11222333000181", type: :cnpj).details[:type]
      assert_equal "cpf", Pix::Key.parse("52998224725", type: "CPF").details[:type]
      assert_error Pix::Key.parse("fulano@example.com", type: :cpf), :invalid_characters
      assert_error Pix::Key.parse("52998224725", type: :email), :invalid_email
      assert_error Pix::Key.parse("52998224725", type: :evp), :invalid_evp
      assert_error Pix::Key.parse("52998224725", type: :phone), :invalid_area_code
      bogus = Pix::Key.parse("52998224725", type: "iban")
      assert_error bogus, :invalid_key_type
      assert_includes bogus.error_messages.join, "cpf, cnpj, phone, email, evp"
    end

    def test_detection
      {
        "+5561912345678" => "phone", "a@b.com" => "email", "123e4567-e12b-12d1-a456-426655440000" => "evp",
        "529.982.247-25" => "cpf", "52998224725" => "cpf", "11.222.333/0001-81" => "cnpj", "12ABC34501DE35" => "cnpj",
        "(61) 91234-5678" => "phone", "nonsense" => nil
      }.each { |text, type| assert_value type, Pix::Key.detect(text), text }
    end

    def test_input_is_bounded
      assert_error Pix::Key.parse("a" * 101), :too_long
      assert_kind_of Result, Pix::Key.parse("\xFF\xFE")
      assert_error Pix::Key.parse(nil), :blank
    end

    def test_types_constant
      assert_equal %w[cpf cnpj phone email evp], Pix::Key::TYPES
    end
  end
end
