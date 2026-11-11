# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "json"
require "minitest/autorun"
require "brkit"

# Minitest assigns its random seed inside Minitest.run. Runners that inspect the test classes earlier
# (embedded interpreters, some IDE integrations) would otherwise hit a nil seed, so set one up front.
Minitest.seed ||= Integer(ENV.fetch("SEED") { Random.new_seed % 65_535 })

module Brkit
  # A random source that replays a fixed list of values (then zeros), to force edge cases in generators.
  class ScriptedRng
    def initialize(*values)
      @values = values
    end

    # Mimics Random#rand for Integer and Range arguments.
    def rand(limit = nil)
      value = @values.empty? ? 0 : @values.shift
      case limit
      when Integer then value % limit
      when Range then limit.begin + (value % (limit.end - limit.begin + 1))
      else 0.5
      end
    end
  end

  # Assertions shared by the test classes.
  module TestHelpers
    # assert_equal that also accepts a nil expectation (Minitest 6 rejects +assert_equal nil, ...+).
    def assert_value(expected, actual, message = nil)
      expected.nil? ? assert_nil(actual, message) : assert_equal(expected, actual, message)
    end

    # Fails unless +result+ is valid, showing the reported problems.
    def assert_valid(result, message = nil)
      assert_predicate result, :valid?, message || "expected valid, got errors: #{result.error_messages.inspect}"
    end

    # Fails unless +result+ is invalid.
    def refute_valid(result, message = nil)
      refute_predicate result, :valid?, message || "expected invalid for #{result.input.inspect}"
    end

    # Fails unless +result+ carries an error with the given +code+.
    def assert_error(result, code, message = nil)
      codes = result.errors.map(&:code)
      assert_includes codes, code, message || "expected error #{code.inspect} for #{result.input.inspect}, got #{codes.inspect}"
    end
  end
end

Minitest::Test.include(Brkit::TestHelpers)
