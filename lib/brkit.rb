# frozen_string_literal: true

require_relative "brkit/version"
require_relative "brkit/errors"
require_relative "brkit/result"
require_relative "brkit/text"
require_relative "brkit/rng"
require_relative "brkit/uf"
require_relative "brkit/mod11"
require_relative "brkit/crc16"
require_relative "brkit/luhn"
require_relative "brkit/cpf"
require_relative "brkit/cnpj"
require_relative "brkit/pis"
require_relative "brkit/phone"
require_relative "brkit/cep"
require_relative "brkit/plate"
require_relative "brkit/card"
require_relative "brkit/pix"
require_relative "brkit/fake"

# Brkit: validators, generators and formatters for Brazilian documents and payloads.
#
# Zero runtime dependencies, offline and deterministic. Every validator returns a {Result}; every generator
# accepts +rng:+ or +seed:+. The library is split by document:
#
# * {CPF}, {CNPJ} (classic and alphanumeric), {PIS}
# * {Pix} (BR Code build/decode) with {CRC16}
# * {Card} with {Luhn}, {Plate}, {Phone}, {CEP}
# * {Fake} for seeded fictitious people
#
# The Rack-compatible JSON API lives in +brkit/api+ and the command line in +brkit/cli+; neither is
# loaded by +require "brkit"+.
module Brkit
end
