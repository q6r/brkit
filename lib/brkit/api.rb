# frozen_string_literal: true

require_relative "../brkit"
require_relative "api/app"
require_relative "api/openapi"

module Brkit
  # The JSON HTTP API: a pure Rack 3 application (+Brkit::API::App+) with no runtime dependency on any gem.
  #
  # Not loaded by +require "brkit"+; use +require "brkit/api"+ and +run Brkit::API::App.new+ in a +config.ru+.
  # See docs/api.md for the endpoints and docs/problems.md for the error types.
  module API
  end
end
