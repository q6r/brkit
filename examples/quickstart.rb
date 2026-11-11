# frozen_string_literal: true

# A tour of the library. Run it from the repository root:
#
#   ruby -Ilib examples/quickstart.rb
require "brkit"

# Validators return a Result and never raise.
result = Brkit::CPF.validate("529.982.247-26")
puts "CPF valid?  #{result.valid?}"
puts "  normalized #{result.normalized}, formatted #{result.formatted}"
result.errors.each { |error| puts "  #{error.code}: #{error.message}" }

# The alphanumeric CNPJ: letters count as their ASCII code minus 48.
cnpj = Brkit::CNPJ.validate("12.ABC.345/01DE-35", explain: true)
puts "\nCNPJ valid? #{cnpj.valid?} (alphanumeric: #{cnpj.details[:alphanumeric]})"
step = cnpj.details[:steps].first
puts "  #{step[:label]}"
puts "  chars   #{step[:chars].join(' ')}"
puts "  values  #{step[:values].join(' ')}"
puts "  weights #{step[:weights].join(' ')}"
puts "  sum #{step[:sum]}, #{step[:sum]} mod 11 = #{step[:remainder]}, check digit #{step[:check_digit]}"

# Generators are deterministic: the same seed always gives the same values.
puts "\nA CPF from São Paulo (seed 7): #{Brkit::CPF.generate(uf: 'SP', formatted: true, seed: 7)}"
puts "Three Mercosul plates (seeds 0 to 2): #{Array.new(3) { |seed| Brkit::Plate.generate(seed: seed) }.join(', ')}"
puts "Legacy plate to Mercosul: ABC-1234 -> #{Brkit::Plate.convert('ABC-1234').normalized}"

# PIX: build a static BR Code, then decode it back.
payload = Brkit::Pix.build(key: "123e4567-e12b-12d1-a456-426655440000", name: "Fulano de Tal",
                           city: "BRASILIA", amount: 12.5, txid: "PED123")
puts "\nPIX copia e cola:\n  #{payload}"
decoded = Brkit::Pix.decode(payload.to_s, explain: true)
crc = decoded.details[:crc]
puts "  valid? #{decoded.valid?}, CRC #{crc[:actual]} (#{crc[:steps].length} bytes hashed)"
puts "  key #{decoded.details[:pix][:key]} (#{decoded.details[:pix][:key_type]}), amount #{decoded.details[:pix][:amount]}"

# A person who does not exist, the same one every time.
person = Brkit::Fake.person(seed: 7)
puts "\n#{person.name}, CPF #{person.cpf}, #{person.address[:city]}/#{person.address[:uf]}"
