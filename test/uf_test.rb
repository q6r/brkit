# frozen_string_literal: true

require_relative "test_helper"

module Brkit
  class UFTest < Minitest::Test
    def test_has_27_units
      assert_equal 27, UF::CODES.length
      assert_equal UF::CODES.sort, UF::CODES
      assert_equal 27, UF::NAMES.values.uniq.length
    end

    def test_normalize
      assert_equal "SP", UF.normalize("sp")
      assert_equal "RJ", UF.normalize(" rj ")
      assert_nil UF.normalize("XX")
      assert_nil UF.normalize("")
      assert_nil UF.normalize(nil)
    end

    def test_name
      assert_equal "São Paulo", UF.name("SP")
      assert_equal "Distrito Federal", UF.name("df")
      assert_nil UF.name("ZZ")
    end

    def test_fetch_raises_with_actionable_message
      assert_equal "MG", UF.fetch("mg")
      error = assert_raises(InvalidInputError) { UF.fetch("XX") }
      assert_equal [:unknown_uf], error.issues.map(&:code)
      assert_includes error.message, "unknown UF"
      assert_includes error.message, "SP"
    end

    def test_fetch_truncates_hostile_values_in_the_message
      error = assert_raises(InvalidInputError) { UF.fetch("x" * 500) }
      assert_operator error.message.length, :<, 300
    end
  end
end
