# frozen_string_literal: true

require_relative "test_helper"

module Brkit
  class RngTest < Minitest::Test
    def test_same_seed_gives_the_same_stream
      first = Rng.resolve(seed: 42)
      second = Rng.resolve(seed: 42)
      assert_equal Array.new(10) { first.rand(1000) }, Array.new(10) { second.rand(1000) }
    end

    def test_seed_matches_a_plain_random
      assert_equal Random.new(42).rand(100), Rng.resolve(seed: 42).rand(100)
      assert_equal 51, Rng.resolve(seed: 42).rand(100)
    end

    def test_different_seeds_diverge
      refute_equal Array.new(5) { Rng.resolve(seed: 1).rand(1_000_000) }, Array.new(5) { Rng.resolve(seed: 2).rand(1_000_000) }
    end

    def test_accepts_an_existing_generator
      random = Random.new(7)
      assert_same random, Rng.resolve(rng: random)
    end

    def test_without_arguments_returns_a_fresh_random
      assert_kind_of Random, Rng.resolve
    end

    def test_rejects_both_rng_and_seed
      error = assert_raises(InvalidInputError) { Rng.resolve(rng: Random.new(1), seed: 1) }
      assert_equal [:invalid_rng], error.issues.map(&:code)
    end

    def test_seed_given_as_text
      assert_equal Rng.resolve(seed: 42).rand(100), Rng.resolve(seed: "42").rand(100)
    end

    def test_accepts_zero_and_large_seeds
      assert_kind_of Random, Rng.resolve(seed: 0)
      assert_kind_of Random, Rng.resolve(seed: Rng::MAX_SEED)
      assert_kind_of Random, Rng.resolve(seed: 2**70)
    end

    def test_rejects_invalid_seeds
      ["abc", "-1", -5, 1.5, "1e3", "", "0x10", [1], Object.new].each do |seed|
        error = assert_raises(InvalidInputError, "seed #{seed.inspect}") { Rng.resolve(seed: seed) }
        assert_equal [:invalid_seed], error.issues.map(&:code)
        assert_equal ["seed"], error.issues.map(&:field)
      end
    end

    def test_pick_uses_only_integer_draws
      random = Random.new(5)
      list = %w[a b c d]
      expected = Random.new(5).then { |twin| list[twin.rand(4)] }
      assert_equal expected, Rng.pick(random, list)
    end

    def test_digits_and_chance
      random = Random.new(3)
      digits = Rng.digits(random, 12)
      assert_equal 12, digits.length
      assert digits.all? { |digit| digit.between?(0, 9) }
      assert_equal [], Rng.digits(random, 0)
      assert_equal true, Rng.chance?(Random.new(1), 100)
      assert_equal false, Rng.chance?(Random.new(1), 0)
    end
  end
end
