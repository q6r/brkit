# frozen_string_literal: true

require_relative "lib/brkit/version"

Gem::Specification.new do |spec|
  spec.name = "brkit"
  spec.version = Brkit::VERSION
  spec.authors = ["q6r"]

  spec.summary = "Kit Brasil: CPF, CNPJ (including the alphanumeric format), PIX BR Code, plates, phones, " \
                 "test cards, CEP and fake people."
  spec.description = <<~TEXT.tr("\n", " ").strip
    Validators, generators and formatters for the documents and payloads Brazilian applications handle:
    CPF, CNPJ (classic and the alphanumeric format in force since July 2026), PIS, PIX BR Code (build,
    decode, CRC16), Luhn-valid test cards, licence plates (including Mercosul conversion), phone numbers,
    CEP and seeded fictitious people. Zero runtime dependencies. Ships a command line, a Rack JSON API and
    an interactive playground that animates the checksums.
  TEXT
  spec.homepage = "https://github.com/q6r/brkit"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1"

  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "source_code_uri" => spec.homepage,
    "changelog_uri" => "#{spec.homepage}/blob/main/CHANGELOG.md",
    "documentation_uri" => "#{spec.homepage}/tree/main/docs",
    "bug_tracker_uri" => "#{spec.homepage}/issues",
    "rubygems_mfa_required" => "true"
  }

  spec.files = Dir["lib/**/*.rb", "public/**/*", "docs/*.md", "exe/*", "config.ru", "LICENSE", "README*.md",
                   "CHANGELOG.md"]
  spec.bindir = "exe"
  spec.executables = ["brkit"]
  spec.require_paths = ["lib"]
end
