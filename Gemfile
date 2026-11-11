# frozen_string_literal: true

source "https://rubygems.org"

# The library itself has no runtime dependencies; see brkit.gemspec.
gemspec

group :development, :test do
  gem "minitest", ">= 5.20"
  gem "rake", "~> 13.0"
  gem "rubocop", "~> 1.76", require: false
end

# Only needed for `brkit serve` / `rackup config.ru`: bundle config set --local with server
group :server, optional: true do
  gem "puma", ">= 6.4"
  gem "rackup", ">= 2.1"
end
