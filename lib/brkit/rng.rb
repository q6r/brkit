# frozen_string_literal: true

module Brkit
  # Random-number plumbing shared by every generator.
  #
  # All generators take +rng:+ (any object that responds to +rand+, normally a
  # +Random+) or +seed:+ (an Integer, which builds +Random.new(seed)+). Passing
  # a seed makes the output reproducible: the same seed always yields the same
  # values, on every platform and Ruby version that implements MT19937.
  module Rng
    # Largest seed accepted by the HTTP API and the CLI (2**32 - 1).
    MAX_SEED = 4_294_967_295

    # How many draws a generator may reject (repeated digits, wrong brand, ...) before giving up.
    MAX_ATTEMPTS = 100

    class << self
      # Resolves the +rng:+/+seed:+ pair every generator accepts.
      #
      # @param rng [#rand, nil] ready-made generator
      # @param seed [Integer, String, nil] seed for a new +Random+
      # @return [#rand]
      # @raise [InvalidInputError] when both are given, or the seed is not a non-negative integer
      def resolve(rng: nil, seed: nil)
        raise InvalidInputError.for(:invalid_rng, "pass either rng: or seed:, not both", field: "seed") if rng && seed
        return rng if rng
        return Random.new if seed.nil?

        Random.new(parse_seed(seed))
      end

      # Picks one element. Uses only +rng.rand(Integer)+ so the choice is stable across Ruby versions.
      def pick(rng, list)
        list[rng.rand(list.size)]
      end

      # @return [Array<Integer>] +count+ random decimal digits
      def digits(rng, count)
        Array.new(count) { rng.rand(10) }
      end

      # @return [Boolean] true with probability +percent+/100
      def chance?(rng, percent)
        rng.rand(100) < percent
      end

      # Runs the block until it returns a truthy value, at most {MAX_ATTEMPTS} times. Generators use it to
      # reject unusable draws without risking an endless loop when handed a degenerate random source.
      #
      # @param description [String] what was being generated, for the error message
      # @return [Object] the first truthy block result
      # @raise [Error] when every attempt was rejected
      def attempt(description)
        MAX_ATTEMPTS.times do
          value = yield
          return value if value
        end
        raise Error, "could not generate #{description}: the random source kept producing rejected values"
      end

      private

      def parse_seed(seed)
        value = seed.is_a?(Integer) ? seed : Integer(seed.to_s, 10)
        raise ArgumentError, "negative" if value.negative?

        value
      rescue ArgumentError
        raise InvalidInputError.for(:invalid_seed, "seed must be a non-negative integer", field: "seed")
      end
    end
  end
end
