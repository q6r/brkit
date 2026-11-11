# frozen_string_literal: true

require_relative "pix/builder"
require_relative "pix/decoder"
require_relative "pix/key"
require_relative "pix/tlv"

module Brkit
  # PIX, the Brazilian instant-payment system: static BR Code payloads ("copia e cola" and QR codes).
  #
  # A BR Code is an EMV QRCPS-MPM payload: a sequence of +ID + length + value+ objects ending in a
  # CRC-16/CCITT-FALSE checksum ({CRC16}). {build} writes one, {decode} reads any.
  #
  #   payload = Brkit::Pix.build(key: "123e4567-e12b-12d1-a456-426655440000",
  #                              name: "Fulano de Tal", city: "BRASILIA")
  #   payload.to_s #=> "00020126580014br.gov.bcb.pix0136123e4567-...63041D3D"
  #   Brkit::Pix.decode(payload.to_s).valid? #=> true
  #
  # The output was checked against the static example printed in the Banco Central "Manual de Padrões
  # para Iniciação do Pix": building it with the same inputs reproduces the manual's payload and its CRC.
  # Rendering a QR image is out of scope; feed the payload to any QR encoder.
  module Pix
    class << self
      # Builds a static payload.
      #
      # @param key [String] PIX key (CPF, CNPJ, mobile phone, e-mail or random key)
      # @param name [String] merchant name, up to 25 characters
      # @param city [String] merchant city, up to 15 characters
      # @param amount [Integer, Float, String, nil] value in reais, at most two decimals; omit for an open amount
      # @param txid [String, nil] reconciliation id, 1-25 letters or digits
      # @param message [String, nil] free text shown to the payer; shares 99 characters with the key
      # @param key_type [String, Symbol, nil] force the key type instead of detecting it
      # @return [Payload] the payload, its CRC and its TLV tree
      # @raise [InvalidInputError] listing every invalid field
      def build(key:, name:, city:, amount: nil, txid: nil, message: nil, key_type: nil)
        Builder.new(key: key, name: name, city: city, amount: amount, txid: txid, message: message,
                    key_type: key_type).build
      end

      # Parses and checks a payload; see {Decoder} for the checks.
      #
      # @param payload [String]
      # @param explain [Boolean] add the CRC register after every byte to +details[:crc][:steps]+
      # @return [Result]
      def decode(payload, explain: false)
        Decoder.call(payload, explain: explain)
      end

      # @return [Boolean] shorthand for +decode(payload).valid?+
      def valid?(payload)
        decode(payload).valid?
      end
    end
  end
end
