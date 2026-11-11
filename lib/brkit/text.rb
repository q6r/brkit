# frozen_string_literal: true

module Brkit
  # Small string helpers shared by the validators.
  # @api private
  module Text
    # Longest input (in characters) the validators examine. Longer values are
    # rejected up front so hostile input cannot trigger expensive work.
    MAX_INPUT_LENGTH = 256

    # Stands in for bytes that are not valid UTF-8.
    REPLACEMENT = "\u{FFFD}"

    class << self
      # Coerces any object into a valid UTF-8 string. Never raises: bytes that
      # cannot be decoded become U+FFFD, which every validator then rejects as
      # an unexpected character.
      #
      # @param value [Object]
      # @return [String]
      def coerce(value)
        string = value.to_s
        unless string.encoding == Encoding::UTF_8
          string = string.encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: REPLACEMENT)
        end
        string.valid_encoding? ? string : string.scrub(REPLACEMENT)
      end

      # Removes diacritics: +"Ação"+ becomes +"Acao"+.
      #
      # @param string [String] valid UTF-8
      # @return [String]
      def fold(string)
        string.unicode_normalize(:nfd).gsub(/\p{Mn}/, "")
      end

      # Lists the distinct characters of +string+ that match +pattern+, quoted for messages.
      #
      # @return [String] for example +"'a', '#'"+
      def describe_chars(string, pattern)
        string.scan(pattern).uniq.first(5).map { |char| char.inspect.tr('"', "'") }.join(", ")
      end
    end
  end
end
