# frozen_string_literal: true

module Brkit
  # The 26 Brazilian states and the Federal District (UF = unidade da federação).
  module UF
    # Two-letter code => official name, alphabetical by code.
    NAMES = {
      "AC" => "Acre", "AL" => "Alagoas", "AM" => "Amazonas", "AP" => "Amapá", "BA" => "Bahia",
      "CE" => "Ceará", "DF" => "Distrito Federal", "ES" => "Espírito Santo", "GO" => "Goiás",
      "MA" => "Maranhão", "MG" => "Minas Gerais", "MS" => "Mato Grosso do Sul", "MT" => "Mato Grosso",
      "PA" => "Pará", "PB" => "Paraíba", "PE" => "Pernambuco", "PI" => "Piauí", "PR" => "Paraná",
      "RJ" => "Rio de Janeiro", "RN" => "Rio Grande do Norte", "RO" => "Rondônia", "RR" => "Roraima",
      "RS" => "Rio Grande do Sul", "SC" => "Santa Catarina", "SE" => "Sergipe", "SP" => "São Paulo",
      "TO" => "Tocantins"
    }.freeze

    # @return [Array<String>] the 27 codes
    CODES = NAMES.keys.freeze

    class << self
      # @param value [#to_s] code in any case, for example +"sp"+
      # @return [String, nil] the upper-case code, or nil when it is not a Brazilian UF
      def normalize(value)
        code = value.to_s.strip.upcase
        NAMES.key?(code) ? code : nil
      end

      # @return [String, nil] official name, e.g. +"São Paulo"+ for +"SP"+
      def name(code)
        NAMES[normalize(code)]
      end

      # Like {.normalize} but raises.
      #
      # @raise [InvalidInputError] when +value+ is not a UF code
      # @return [String]
      def fetch(value)
        normalize(value) ||
          raise(InvalidInputError.for(:unknown_uf, "unknown UF #{value.to_s[0, 16].inspect}; use one of #{CODES.join(', ')}",
                                      field: "uf"))
      end
    end
  end
end
