# frozen_string_literal: true

# Rack entry point for the JSON API and the playground (public/).
#
#   bundle exec rackup config.ru --host 127.0.0.1 --port 9292
#   bundle exec puma config.ru
#   brkit serve
#
# Settings come from the BRKIT_* environment variables (see docs/api.md); a bad value stops the boot with a
# message that names the variable.
require_relative "lib/brkit/api"

run Brkit::API::App.new
