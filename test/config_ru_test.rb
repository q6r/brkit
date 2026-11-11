# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/rack_helpers"

module Brkit
  # config.ru is what +rackup+, +puma+ and +brkit serve+ load; evaluate it against a stand-in for Rack::Builder.
  class ConfigRuTest < Minitest::Test
    ROOT = File.expand_path("..", __dir__)

    # Provides the one method config.ru needs from Rack::Builder.
    class FakeBuilder
      attr_reader :app

      def run(app)
        @app = app
      end
    end

    def load_config
      path = File.join(ROOT, "config.ru")
      builder = FakeBuilder.new
      builder.instance_eval(File.read(path), path)
      builder.app
    end

    def test_config_ru_runs_the_api_application
      app = load_config
      assert_kind_of API::App, app
      reply = request(app, :get, "/healthz")
      assert_equal 200, reply.status
      assert_equal VERSION, reply.json["version"]
    end

    def test_the_application_serves_the_playground_from_public
      reply = request(load_config, :get, "/")
      assert_equal 200, reply.status
      assert_includes reply.header("content-type"), "text/html"
      assert_includes reply.header("content-security-policy"), "script-src 'self'"
    end
  end
end
