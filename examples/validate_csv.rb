# frozen_string_literal: true

# Validates a "kind,value,expected" list (documents.csv by default) and prints one verdict per row. Exits with
# status 1 when a verdict differs from the expected column, like a data-quality gate in a pipeline would.
#
#   ruby -Ilib examples/validate_csv.rb [path]
require "brkit"

LIBRARIES = {
  "cpf" => Brkit::CPF, "cnpj" => Brkit::CNPJ, "pis" => Brkit::PIS, "card" => Brkit::Card,
  "plate" => Brkit::Plate, "phone" => Brkit::Phone, "cep" => Brkit::CEP
}.freeze

path = ARGV.fetch(0) { File.expand_path("samples/documents.csv", __dir__) }
rows = File.readlines(path, chomp: true).drop(1).map { |line| line.split(",", 3) }

mismatches = 0
rows.each do |kind, value, expected|
  result = LIBRARIES.fetch(kind).validate(value)
  verdict = result.valid? ? "valid" : "invalid"
  mismatches += 1 unless verdict == expected
  reason = result.errors.first&.message
  puts format("%-6s %-22s %-8s %s", kind, value, verdict, reason)
end

puts "\n#{rows.length} rows, #{mismatches} unexpected"
exit(mismatches.zero? ? 0 : 1)
