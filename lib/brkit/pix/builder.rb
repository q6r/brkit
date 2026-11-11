# frozen_string_literal: true

require_relative "../crc16"
require_relative "../errors"
require_relative "../result"
require_relative "../text"
require_relative "key"
require_relative "tlv"

module Brkit
  module Pix
    # A built BR Code payload.
    #
    # @!attribute [r] payload
    #   @return [String] the "copia e cola" text, ending in the CRC
    # @!attribute [r] crc
    #   @return [String] the four hexadecimal characters of field 63
    # @!attribute [r] fields
    #   @return [Array<Field>] the payload as a TLV tree
    # @!attribute [r] key_type
    #   @return [String] one of {Key::TYPES}
    Payload = Struct.new(:payload, :crc, :fields, :key_type, keyword_init: true) do
      # @return [String] the payload text
      def to_s
        payload
      end

      # @return [Hash{Symbol=>Object}] JSON-friendly representation
      def to_h
        { payload: payload, crc: crc, key_type: key_type, fields: fields.map(&:to_h) }
      end
    end

    # Assembles a static PIX payload (the QR code a merchant prints) and reports every problem at once.
    #
    # Field limits come from the BR Code and PIX manuals: name 25, city 15, txid 25 letters or digits,
    # infoAdicional 72, and the whole merchant-account template (key plus message) 99 characters.
    # Text is stripped of accents and must be printable ASCII.
    class Builder
      MAX_NAME = 25
      MAX_CITY = 15
      MAX_MESSAGE = 72
      MAX_TXID = 25
      NO_TXID = "***"
      TEMPLATE_LIMIT = 99
      MAX_INTEGER_DIGITS = 10
      AMOUNT = /\A(?<whole>\d+)(?:[.,](?<cents>\d{1,2}))?\z/
      PRINTABLE = /\A[\x20-\x7E]+\z/
      # Characters taken by the GUI object inside the merchant-account template (ID, length, value).
      GUI_FIELD_LENGTH = TLV::PIX_GUI.length + 4

      # @param key [String] PIX key, see {Key}
      # @param name [String] merchant name, up to 25 characters
      # @param city [String] merchant city, up to 15 characters
      # @param amount [Integer, Float, String, nil] value in reais; omit to let the payer type it
      # @param txid [String, nil] reconciliation id, 1-25 letters or digits; +"***"+ when omitted
      # @param message [String, nil] free text shown to the payer (infoAdicional)
      # @param key_type [String, Symbol, nil] force the key type instead of detecting it
      def initialize(key:, name:, city:, amount: nil, txid: nil, message: nil, key_type: nil)
        @inputs = { key: key, name: name, city: city, amount: amount, txid: txid, message: message }
        @key_type = key_type
        @issues = []
      end

      # @return [Payload]
      # @raise [InvalidInputError] listing every invalid field
      def build
        key = key_value
        values = {
          name: text(:name, MAX_NAME, required: true), city: text(:city, MAX_CITY, required: true),
          amount: amount_value, txid: txid_value, message: text(:message, MAX_MESSAGE, required: false)
        }
        check_template_length(key, values[:message])
        raise InvalidInputError.new(@issues) unless @issues.empty?

        assemble(key, values)
      end

      private

      def key_value
        result = Key.parse(@inputs[:key], type: @key_type)
        result.errors.each { |issue| add(issue.code, issue.message, :key) }
        result.valid? ? result : nil
      end

      def add(code, message, field)
        @issues << Issue.new(code: code, message: message, field: field.to_s)
        nil
      end

      # Normalises a free-text field: accents removed, whitespace collapsed, printable ASCII only.
      def text(field, max, required:)
        value = @inputs[field]
        cleaned = value.nil? ? "" : Text.fold(Text.coerce(value)).gsub(/\s+/, " ").strip
        return (required ? add(:missing, "#{field} is required", field) : nil) if cleaned.empty?

        unless cleaned.match?(PRINTABLE)
          return add(:invalid_characters, "#{field} must be plain ASCII text (accents are removed automatically)",
                     field)
        end
        return add(:too_long, "#{field} can have at most #{max} characters, got #{cleaned.length}", field) if
          cleaned.length > max

        cleaned
      end

      def txid_value
        raw = @inputs[:txid]
        value = raw.nil? ? "" : Text.coerce(raw).strip
        return NO_TXID if value.empty? || value == NO_TXID
        return value if value.match?(/\A[A-Za-z0-9]{1,#{MAX_TXID}}\z/)

        add(:invalid_txid, "txid must be 1 to #{MAX_TXID} letters or digits", :txid)
      end

      # Returns the amount as written in the payload ("12.50"), or nil when absent or invalid.
      def amount_value
        raw = @inputs[:amount]
        return nil if raw.nil? || (raw.is_a?(String) && raw.strip.empty?)

        match = AMOUNT.match(amount_text(raw))
        unless match
          return add(:invalid_amount, "amount must be a plain number with at most two decimals, e.g. 12.50", :amount)
        end

        whole = match[:whole].sub(/\A0+(?=\d)/, "")
        cents = match[:cents].to_s.ljust(2, "0")
        return add(:amount_too_large, "amount can have at most #{MAX_INTEGER_DIGITS} integer digits", :amount) if
          whole.length > MAX_INTEGER_DIGITS
        return add(:invalid_amount, "amount must be greater than zero", :amount) if whole.to_i.zero? && cents.to_i.zero?

        "#{whole}.#{cents}"
      end

      # Floats use their shortest round-trip text so 12.5 reads "12.5" and 0.1 + 0.2 is rejected, not rounded.
      def amount_text(raw)
        case raw
        when Integer then raw.to_s
        when Float then raw.finite? ? raw.to_s : ""
        when String then raw.strip
        else ""
        end
      end

      def check_template_length(key, message)
        return unless key

        key_field = 4 + key.normalized.length
        message_field = message ? 4 + message.length : 0
        return if GUI_FIELD_LENGTH + key_field + message_field <= TEMPLATE_LIMIT

        room = [TEMPLATE_LIMIT - GUI_FIELD_LENGTH - key_field - 4, 0].max
        add(:template_too_long,
            "the key and the message share #{TEMPLATE_LIMIT} characters; with this key the message can have " \
            "at most #{room}", message ? :message : :key)
      end

      def assemble(key, values)
        fields = [TLV.primitive("00", "01"), account_template(key.normalized, values[:message]),
                  TLV.primitive("52", "0000"), TLV.primitive("53", "986")]
        fields << TLV.primitive("54", values[:amount]) if values[:amount]
        fields.push(TLV.primitive("58", "BR"), TLV.primitive("59", values[:name]), TLV.primitive("60", values[:city]),
                    additional_data(values[:txid]))
        finish(fields, key.details[:type])
      end

      def account_template(key, message)
        children = [TLV.primitive("00", TLV::PIX_GUI, name: "Globally Unique Identifier"),
                    TLV.primitive("01", key, name: TLV::PIX_NAMES["01"])]
        children << TLV.primitive("02", message, name: TLV::PIX_NAMES["02"]) if message
        TLV.template("26", children)
      end

      def additional_data(txid)
        TLV.template("62", [TLV.primitive("05", txid, name: TLV::ADDITIONAL_DATA_NAMES["05"])])
      end

      def finish(fields, key_type)
        body = "#{fields.map(&:encode).join}6304"
        crc = CRC16.hex(body)
        Payload.new(payload: "#{body}#{crc}", crc: crc, fields: fields + [TLV.primitive("63", crc)],
                    key_type: key_type)
      end
    end
  end
end
