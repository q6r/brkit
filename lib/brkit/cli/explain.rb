# frozen_string_literal: true

require_relative "style"

module Brkit
  class CLI
    # Renders the "show your work" checksum data (+details[:steps]+) as aligned text.
    # @api private
    module Explain
      # Room for the longest row label ("products") plus one space.
      LABEL_WIDTH = 9
      # Marks the digits Luhn doubles.
      DOUBLED = "x2"

      class << self
        # @param details [Hash] the +details+ of a validation {Result}
        # @param style [Style] colours the titles, row labels and verdicts (plain by default)
        # @return [Array<String>] lines (empty when the result carries no steps)
        def lines(details, style = Style::PLAIN)
          steps = details[:steps]
          return [] unless steps
          return luhn(steps, style) if steps.is_a?(Hash)

          steps.flat_map { |step| mod11(step, style) }
        end

        private

        def mod11(step, style)
          width = [step[:chars], step[:values], step[:weights], step[:products]].flatten.map { |cell| cell.to_s.length }.max
          lines = [style.paint("  #{step[:label]}:", :bold), row("chars", step[:chars], width, style)]
          lines << row("values", step[:values], width, style) if step[:values].map(&:to_s) != step[:chars]
          lines << row("weights", step[:weights], width, style)
          lines << row("products", step[:products], width, style)
          verdict = step[:match] ? style.paint("ok", :green) : style.paint("MISMATCH", :bold, :red)
          lines << "    sum #{step[:sum]}; #{step[:sum]} mod #{step[:modulus]} = #{step[:remainder]}; " \
                   "check digit #{step[:check_digit]} (input has #{step[:actual]}: #{verdict})"
        end

        def luhn(steps, style)
          entries = steps[:entries]
          width = entries.flat_map { |entry| [entry[:digit], entry[:contribution]] }.map { |cell| cell.to_s.length }
                         .push(DOUBLED.length).max
          [
            style.paint("  Luhn, digits from the right:", :bold),
            row("digits", entries.map { |entry| entry[:digit] }, width, style),
            row("doubled", entries.map { |entry| entry[:doubled] ? DOUBLED : "" }, width, style),
            row("counts", entries.map { |entry| entry[:contribution] }, width, style),
            "    sum #{steps[:sum]}; #{steps[:sum]} mod 10 = #{steps[:remainder]} (valid when 0)"
          ]
        end

        def row(label, cells, width, style)
          "    #{style.paint(label.ljust(LABEL_WIDTH), :dim)}#{cells.map { |cell| cell.to_s.rjust(width) }.join(' ')}"
        end
      end
    end
  end
end
