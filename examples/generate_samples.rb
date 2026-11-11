# frozen_string_literal: true

# Regenerates examples/samples/*. Every value comes from a fixed seed, so running it again changes nothing.
#
#   ruby -Ilib examples/generate_samples.rb
require "fileutils"
require "json"
require "brkit"

SAMPLES = File.expand_path("samples", __dir__)
FileUtils.mkdir_p(SAMPLES)

# Ten fictitious people (names, a checksum-valid CPF, e-mail on example.org, phone, address).
people = Brkit::Fake.people(10, seed: 2026)
File.write(File.join(SAMPLES, "people.json"), "#{JSON.pretty_generate(people.map(&:to_h))}\n")

# A mixed list to clean: five valid values per document and one broken value each.
GENERATORS = {
  "cpf" => ->(seed) { Brkit::CPF.generate(formatted: true, seed: seed) },
  "cnpj" => ->(seed) { Brkit::CNPJ.generate(alphanumeric: seed.odd?, formatted: true, seed: seed) },
  "pis" => ->(seed) { Brkit::PIS.generate(formatted: true, seed: seed) },
  "card" => ->(seed) { Brkit::Card.group(Brkit::Card.generate(seed: seed)) },
  "plate" => ->(seed) { Brkit::Plate.generate(layout: seed.even? ? :mercosul : :legacy, formatted: true, seed: seed) },
  "phone" => ->(seed) { Brkit::Phone.generate(formatted: true, seed: seed) },
  "cep" => ->(seed) { Brkit::CEP.generate(formatted: true, seed: seed) }
}.freeze

# Breaks a value in the way a typing mistake would: a changed last digit, or a dropped character.
def break_value(kind, value)
  return value.sub(/.\z/, "") if %w[plate phone cep].include?(kind)

  value[0...-1] + ((value[-1].to_i + 1) % 10).to_s
end

rows = ["kind,value,expected"]
GENERATORS.each do |kind, generator|
  values = Array.new(5) { |index| generator.call(index + 1) }
  values.each { |value| rows << "#{kind},#{value},valid" }
  rows << "#{kind},#{break_value(kind, values.first)},invalid"
end
File.write(File.join(SAMPLES, "documents.csv"), "#{rows.join("\n")}\n")

# BR Codes: one built here, the Banco Central manual's example, and a tampered copy.
built = Brkit::Pix.build(key: "contato@example.com", name: "Padaria Estrela", city: "Curitiba", amount: "27.90",
                         txid: "PAD0042", message: "Pao e cafe").to_s
manual = "00020126580014br.gov.bcb.pix0136123e4567-e12b-12d1-a456-4266554400005204000053039865802BR5913" \
         "Fulano de Tal6008BRASILIA62070503***63041D3D"
File.write(File.join(SAMPLES, "pix-payloads.txt"), "#{[built, manual, manual.sub('Fulano', 'Fulana')].join("\n")}\n")

puts "wrote people.json, documents.csv and pix-payloads.txt to examples/samples/"
