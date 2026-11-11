# frozen_string_literal: true

module Brkit
  class CLI
    # Optional ANSI colour for the human-readable output; JSON and generated values are never coloured.
    # @api private
    class Style
      CODES = { bold: "1", dim: "2", red: "31", green: "32", yellow: "33", cyan: "36" }.freeze
      RESET = "\e[0m"

      # @param enabled [Boolean] false makes every call return its text unchanged
      def initialize(enabled)
        @enabled = enabled
      end

      # @param text [#to_s]
      # @param names [Array<Symbol>] keys of {CODES}, for example +:bold, :green+
      # @return [String]
      def paint(text, *names)
        return text.to_s unless @enabled

        "\e[#{names.map { |name| CODES.fetch(name) }.join(';')}m#{text}#{RESET}"
      end

      # A style that never colours anything.
      PLAIN = new(false)
    end
  end
end
