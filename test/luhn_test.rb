# frozen_string_literal: true

require_relative "test_helper"

module Brkit
  class LuhnTest < Minitest::Test
    # 79927398713 is the worked example of the Luhn algorithm; the card numbers are the sandbox numbers that
    # payment processors publish for each network.
    VALID = %w[
      79927398713 4111111111111111 5555555555554444 378282246310005 6011111111111117 3530111333300000
      30569309025904 4012888888881881 00
    ].freeze

    # Numbers produced by an independent implementation (Node.js): random payload completed with its check digit.
    ORACLE_VALID = %w[0157764853858436237 073954016803165 0406648443943921956 878602438219 23630420444884].freeze

    def test_accepts_valid_numbers
      (VALID + ORACLE_VALID).each { |number| assert Luhn.valid?(number), "#{number} should pass the Luhn check" }
    end

    def test_rejects_a_changed_digit
      (VALID - ["00"]).each do |number|
        last = number[-1].to_i
        wrong = "#{number[0...-1]}#{(last + 1) % 10}"
        refute Luhn.valid?(wrong), "#{wrong} should fail the Luhn check"
      end
    end

    def test_single_digit_substitutions_are_always_detected
      number = "4111111111111111"
      number.length.times do |index|
        (0..9).each do |digit|
          next if digit.to_s == number[index]

          mutated = number.dup
          mutated[index] = digit.to_s
          refute Luhn.valid?(mutated), "#{mutated} (digit #{index} -> #{digit}) passed"
        end
      end
    end

    def test_rejects_malformed_input
      ["", "0", "4111 1111", "abcd", "4111-1111-1111-1111", "4111111111111111\n"].each do |input|
        refute Luhn.valid?(input), "#{input.inspect} should be rejected"
      end
    end

    def test_check_digit_and_complete
      assert_equal 3, Luhn.check_digit("7992739871")
      assert_equal "79927398713", Luhn.complete("7992739871")
      assert_equal "4111111111111111", Luhn.complete("411111111111111")
      assert_equal 0, Luhn.check_digit("0")
    end

    def test_complete_always_yields_a_valid_number
      random = Random.new(2026)
      300.times do
        payload = Array.new(random.rand(5..18)) { random.rand(10) }.join
        assert Luhn.valid?(Luhn.complete(payload)), "complete(#{payload}) is not valid"
      end
    end

    def test_steps_replay_the_computation
      steps = Luhn.steps("79927398713")
      assert_equal 11, steps[:entries].length
      assert_equal 70, steps[:sum]
      assert_equal 0, steps[:remainder]
      assert_equal({ digit: 3, doubled: false, contribution: 3 }, steps[:entries].first)
      assert_equal({ digit: 1, doubled: true, contribution: 2 }, steps[:entries][1])
      assert_equal({ digit: 8, doubled: true, contribution: 7 }, steps[:entries][3])
    end

    def test_steps_flag_an_invalid_number
      refute_equal 0, Luhn.steps("4111111111111112")[:remainder]
    end
  end
end
