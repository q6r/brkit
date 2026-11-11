# frozen_string_literal: true

require_relative "../errors"

module Brkit
  module Pix
    # One data object of an EMV QR code (BR Code) payload: +ID + 2-digit length + value+.
    #
    # @!attribute [r] id
    #   @return [String] two-digit identifier
    # @!attribute [r] name
    #   @return [String, nil] human-readable name when the identifier is known
    # @!attribute [r] length
    #   @return [Integer] number of characters in +value+
    # @!attribute [r] value
    #   @return [String] raw value (for templates, the concatenation of the children)
    # @!attribute [r] children
    #   @return [Array<Field>, nil] nested objects for template fields, otherwise nil
    Field = Struct.new(:id, :name, :length, :value, :children, keyword_init: true) do
      # @return [Hash{Symbol=>Object}] JSON-friendly tree (+name+ and +children+ omitted when absent)
      def to_h
        hash = { id: id, name: name, length: length, value: value }.compact
        hash[:children] = children.map(&:to_h) if children
        hash
      end

      # @return [String] the field written back as TLV
      def encode
        "#{id}#{length.to_s.rjust(2, '0')}#{value}"
      end
    end

    # Reads and writes the TLV structure of BR Code payloads.
    #
    # Only the identifiers that hold nested objects are expanded: 26-51 (merchant account
    # information, where PIX lives), 62 (additional data), 64 (language template) and 80-99
    # (unreserved templates). Lengths are counted in characters.
    module TLV
      MAX_VALUE_LENGTH = 99
      PIX_GUI = "br.gov.bcb.pix"

      ROOT_NAMES = {
        "00" => "Payload Format Indicator", "01" => "Point of Initiation Method",
        "52" => "Merchant Category Code", "53" => "Transaction Currency", "54" => "Transaction Amount",
        "55" => "Tip or Convenience Indicator", "56" => "Value of Convenience Fee Fixed",
        "57" => "Value of Convenience Fee Percentage", "58" => "Country Code", "59" => "Merchant Name",
        "60" => "Merchant City", "61" => "Postal Code", "62" => "Additional Data Field Template",
        "63" => "CRC", "64" => "Merchant Information, Language Template"
      }.freeze

      PIX_NAMES = {
        "01" => "Pix key (chave)", "02" => "Additional info (infoAdicional)",
        "03" => "Withdrawal service facilitator ISPB (fss)", "25" => "Payload URL"
      }.freeze

      ADDITIONAL_DATA_NAMES = {
        "01" => "Bill Number", "02" => "Mobile Number", "03" => "Store Label", "04" => "Loyalty Number",
        "05" => "Reference Label (txid)", "06" => "Customer Label", "07" => "Terminal Label",
        "08" => "Purpose of Transaction", "09" => "Additional Consumer Data Request"
      }.freeze

      LANGUAGE_NAMES = {
        "00" => "Language Preference", "01" => "Merchant Name, Alternate Language",
        "02" => "Merchant City, Alternate Language"
      }.freeze

      class << self
        # Parses a payload into its field tree.
        #
        # @param text [String] the payload
        # @return [Array<Field>] root fields in order of appearance
        # @raise [ParseError] when an identifier or length is not numeric, or a value is truncated
        def parse(text)
          scan(text, 0).map { |entry| template?(entry[:id]) ? build_template(entry) : build_primitive(entry) }
        end

        # @param id [String] two-digit identifier
        # @return [Boolean] true when the identifier holds nested objects
        def template?(id)
          number = id.to_i
          (26..51).cover?(number) || [62, 64].include?(number) || (80..99).cover?(number)
        end

        # Builds a primitive field.
        #
        # @param id [String]
        # @param value [String] at most 99 characters
        # @return [Field]
        # @raise [InvalidInputError] when the value is longer than 99 characters
        def primitive(id, value, name: nil)
          check_length!(id, value)
          Field.new(id: id, name: name || ROOT_NAMES[id], length: value.length, value: value)
        end

        # Builds a template field from already built children.
        #
        # @param id [String]
        # @param children [Array<Field>]
        # @return [Field]
        # @raise [InvalidInputError] when the combined value is longer than 99 characters
        def template(id, children)
          value = children.map(&:encode).join
          check_length!(id, value)
          Field.new(id: id, name: root_name(id), length: value.length, value: value, children: children)
        end

        # @param id [String] root identifier
        # @return [String, nil]
        def root_name(id)
          return ROOT_NAMES[id] if ROOT_NAMES.key?(id)

          number = id.to_i
          return "Merchant Account Information" if (2..51).cover?(number)
          return "Unreserved Template" if (80..99).cover?(number)

          "Reserved for EMVCo" if (65..79).cover?(number)
        end

        # @param parent_id [String] identifier of the enclosing template
        # @param id [String] identifier of the nested object
        # @param gui [String, nil] value of the template's +00+ (GUI) object
        # @return [String, nil]
        def child_name(parent_id, id, gui)
          case parent_id
          when "62" then ADDITIONAL_DATA_NAMES[id]
          when "64" then LANGUAGE_NAMES[id]
          else
            return "Globally Unique Identifier" if id == "00"

            PIX_NAMES[id] if pix_gui?(gui)
          end
        end

        # @return [Boolean] true when +gui+ identifies the PIX arrangement (case-insensitive)
        def pix_gui?(gui)
          gui.to_s.casecmp?(PIX_GUI)
        end

        private

        # Splits +text+ into raw entries. +base+ is the offset of +text+ inside the whole payload.
        def scan(text, base)
          entries = []
          position = 0
          while position < text.length
            header = text[position, 4]
            unless header.match?(/\A\d{4}\z/)
              raise ParseError.new("expected a 2-digit ID and a 2-digit length at position #{base + position}",
                                   position: base + position)
            end

            length = header[2, 2].to_i
            value = text[position + 4, length]
            if value.length < length
              raise ParseError.new("field #{header[0, 2]} declares #{length} characters but only #{value.length} remain",
                                   position: base + position)
            end

            entries << { id: header[0, 2], length: length, value: value, offset: base + position + 4 }
            position += 4 + length
          end
          entries
        end

        def build_primitive(entry)
          Field.new(id: entry[:id], name: root_name(entry[:id]), length: entry[:length], value: entry[:value])
        end

        def build_template(entry)
          raw = scan(entry[:value], entry[:offset])
          gui = raw.find { |child| child[:id] == "00" }&.fetch(:value)
          children = raw.map do |child|
            Field.new(id: child[:id], name: child_name(entry[:id], child[:id], gui),
                      length: child[:length], value: child[:value])
          end
          Field.new(id: entry[:id], name: root_name(entry[:id]), length: entry[:length], value: entry[:value],
                    children: children)
        end

        def check_length!(id, value)
          return if value.length <= MAX_VALUE_LENGTH

          raise InvalidInputError.for(:field_too_long,
                                      "field #{id} would hold #{value.length} characters; the limit is #{MAX_VALUE_LENGTH}")
        end
      end
    end
  end
end
