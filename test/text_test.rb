# frozen_string_literal: true

require_relative "test_helper"

module Brkit
  class TextTest < Minitest::Test
    def test_coerce_passes_valid_utf8_through
      assert_equal "Ação", Text.coerce("Ação")
    end

    def test_coerce_converts_other_objects
      assert_equal "", Text.coerce(nil)
      assert_equal "52998224725", Text.coerce(52_998_224_725)
      assert_equal "abc", Text.coerce(:abc)
    end

    def test_coerce_replaces_invalid_utf8
      result = Text.coerce("ab\xFFcd")
      assert_equal Encoding::UTF_8, result.encoding
      assert_predicate result, :valid_encoding?
      assert_equal "ab\u{FFFD}cd", result
    end

    def test_coerce_handles_binary_and_foreign_encodings
      assert_equal "a\u{FFFD}", Text.coerce("a\xE9".b)
      assert_equal "ab", Text.coerce("ab".b)
      assert_equal "é", Text.coerce("é".encode(Encoding::ISO_8859_1))
      assert_equal "ok", Text.coerce("ok".encode(Encoding::UTF_16LE))
    end

    def test_fold_removes_diacritics
      assert_equal "Acao Cafe Uniao", Text.fold("Ação Café União")
      assert_equal "plain", Text.fold("plain")
    end

    def test_describe_chars_lists_distinct_offenders
      assert_equal "'a', '#'", Text.describe_chars("aa#a", /[a#]/)
      assert_equal "", Text.describe_chars("123", /[a-z]/)
    end

    def test_describe_chars_limits_the_list
      assert_equal 5, Text.describe_chars("abcdefgh", /[a-z]/).split(", ").length
    end
  end
end
