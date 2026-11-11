# frozen_string_literal: true

require_relative "../crc16"
require_relative "../errors"
require_relative "../result"
require_relative "../text"
require_relative "key"
require_relative "tlv"

module Brkit
  module Pix
    # Parses a BR Code payload into its TLV tree and checks it against the BR Code manual (v2.0.1).
    #
    # The checks are: the payload format indicator (+000201+), unique root identifiers, the mandatory
    # fields (52, 53, 58, 59, 60, 62 with its reference label, and at least one merchant-account template),
    # fixed values (currency 986, country BR), the length limits of name (25) and city (15), the CRC field
    # being last, and the CRC itself. It never raises on bad input: every problem becomes an {Issue}.
    class Decoder
      # Longest payload examined; a safety bound, not a limit of the BR Code format.
      MAX_LENGTH = 2_048
      REQUIRED = {
        "52" => "Merchant Category Code", "53" => "Transaction Currency", "58" => "Country Code",
        "59" => "Merchant Name", "60" => "Merchant City", "62" => "Additional Data Field Template"
      }.freeze
      FIXED_VALUES = { "53" => "986", "58" => "BR" }.freeze
      LENGTH_LIMITS = { "59" => 25, "60" => 15 }.freeze

      # @param input [String] payload text
      # @param explain [Boolean] add the CRC register after every byte to +details[:crc][:steps]+
      # @return [Result]
      def self.call(input, explain: false)
        new(input, explain: explain).call
      end

      def initialize(input, explain: false)
        @text = Text.coerce(input).strip
        @explain = explain
      end

      # @return [Result] +details+ has +:length+, +:crc+ (+expected+, +actual+, +valid+, and +steps+ when asked
      #   for), +:fields+ and +:pix+
      def call
        problem = text_problem
        return outcome([problem]) if problem

        analyse(TLV.parse(@text))
      rescue ParseError => e
        outcome([Issue.new(code: :malformed_tlv, message: e.message)], position: e.position)
      end

      private

      def text_problem
        if @text.empty?
          Issue.new(code: :blank, message: "payload is empty")
        elsif @text.length > MAX_LENGTH
          Issue.new(code: :too_long, message: "payload is longer than #{MAX_LENGTH} characters")
        elsif @text.match?(/[[:cntrl:]]/)
          Issue.new(code: :control_characters, message: "payload must be a single line without control characters")
        end
      end

      def analyse(fields)
        root = fields.group_by(&:id)
        crc = crc_details(fields)
        pix = pix_summary(root)
        issues = format_issues(fields) + duplicate_issues(root) + missing_issues(root) + value_issues(root)
        issues.concat(pix_issues(pix))
        issues << crc_issue(crc) if crc && !crc[:valid]
        outcome(issues, fields: fields, crc: crc, pix: pix)
      end

      def crc_details(fields)
        last = fields.last
        return nil unless last.id == "63" && last.length == 4

        covered = @text[0...-4]
        expected = CRC16.hex(covered)
        crc = { expected: expected, actual: last.value.upcase, valid: last.value.upcase == expected }
        crc[:steps] = CRC16.trace(covered) if @explain
        crc
      end

      def crc_issue(crc)
        issue(:crc_mismatch, "CRC mismatch: the payload carries #{crc[:actual]} but its content hashes to " \
                             "#{crc[:expected]}", "63")
      end

      def format_issues(fields)
        issues = []
        first = fields.first
        last = fields.last
        issues << issue(:bad_format_indicator, "the payload must start with 000201", "00") unless
          first.id == "00" && first.value == "01"
        issues << issue(:missing_crc, "the payload must end with the CRC field (6304 + 4 hex digits)", "63") unless
          last.id == "63" && last.length == 4
        issues
      end

      def duplicate_issues(root)
        root.select { |_id, list| list.length > 1 }.map do |id, list|
          issue(:duplicate_field, "field #{id} appears #{list.length} times", id)
        end
      end

      def missing_issues(root)
        issues = REQUIRED.reject { |id, _name| root.key?(id) }.map do |id, name|
          issue(:missing_field, "field #{id} (#{name}) is required", id)
        end
        unless root.keys.any? { |id| (2..51).cover?(id.to_i) }
          issues << issue(:missing_field, "a merchant account information field (IDs 02-51) is required", "26")
        end
        issues
      end

      def value_issues(root)
        issues = FIXED_VALUES.filter_map do |id, expected|
          field = first_of(root, id)
          next if field.nil? || field.value == expected

          issue(:unexpected_value, "field #{id} must be #{expected}, got #{field.value.inspect}", id)
        end
        issues.concat(length_issues(root))
        issues.concat(amount_issues(first_of(root, "54")))
        issues.concat(reference_issues(first_of(root, "62")))
      end

      def length_issues(root)
        LENGTH_LIMITS.filter_map do |id, max|
          field = first_of(root, id)
          next if field.nil? || field.length.between?(1, max)

          issue(:field_length, "field #{id} (#{field.name}) has 1 to #{max} characters", id)
        end
      end

      def amount_issues(field)
        return [] if field.nil? || field.value.match?(/\A\d+(\.\d+)?\z/)

        [issue(:invalid_amount, "field 54 (amount) must be a decimal number such as 12.50", "54")]
      end

      def reference_issues(template)
        return [] unless template

        label = template.children&.find { |child| child.id == "05" }
        return [issue(:missing_field, "field 62 must contain the reference label (05)", "62")] unless label
        return [] if label.length.between?(1, 25)

        [issue(:field_length, "the reference label (62-05) has 1 to 25 characters", "62")]
      end

      def pix_issues(pix)
        return [] unless pix && pix[:key].nil? && pix[:url].nil?

        [issue(:missing_pix_key, "the PIX template needs a key (01) or a payload URL (25)", pix[:template])]
      end

      # Facts about the PIX template, when the payload has one (GUI br.gov.bcb.pix, case-insensitive).
      def pix_summary(root)
        template = root.select { |id, _list| (26..51).cover?(id.to_i) }.values.flatten.find do |field|
          field.children&.any? { |child| child.id == "00" && TLV.pix_gui?(child.value) }
        end
        return nil unless template

        key = child_value(template, "01")
        url = child_value(template, "25")
        {
          template: template.id, key: key, key_type: key && Key.detect(key), message: child_value(template, "02"),
          url: url, fss: child_value(template, "03"), dynamic: !url.nil?,
          single_use: first_of(root, "01")&.value == "12", amount: first_of(root, "54")&.value,
          merchant_name: first_of(root, "59")&.value, merchant_city: first_of(root, "60")&.value,
          txid: child_value(first_of(root, "62"), "05")
        }
      end

      def first_of(root, id)
        root[id]&.first
      end

      def child_value(template, id)
        template&.children&.find { |child| child.id == id }&.value
      end

      def issue(code, message, field)
        Issue.new(code: code, message: message, field: field)
      end

      def outcome(issues, fields: nil, crc: nil, pix: nil, position: nil)
        details = { length: @text.length }
        details[:position] = position if position
        details[:crc] = crc if crc
        if fields
          details[:fields] = fields.map(&:to_h)
          details[:pix] = pix
        end
        Result.new(kind: "pix", input: @text, normalized: @text.empty? ? nil : @text, errors: issues, details: details)
      end
    end
  end
end
