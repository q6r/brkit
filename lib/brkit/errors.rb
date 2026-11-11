# frozen_string_literal: true

module Brkit
  # Base class of every exception raised on purpose by the library.
  class Error < StandardError; end

  # Raised when an argument handed to a formatter, generator or builder is
  # unusable. Validators never raise this: they return a {Result} instead.
  class InvalidInputError < Error
    # @return [Array<Issue>] every problem found, each tagged with the offending field when known
    attr_reader :issues

    # @param issues [Array<Issue>, Issue, String] problems, or a single message
    def initialize(issues)
      @issues = Array(issues).map { |item| item.is_a?(Issue) ? item : Issue.new(code: :invalid, message: item.to_s) }
      @issues.freeze
      super(@issues.map(&:message).join("; "))
    end

    # Convenience constructor for a single problem.
    # @return [InvalidInputError]
    def self.for(code, message, field: nil)
      new([Issue.new(code: code, message: message, field: field)])
    end
  end

  # Raised by the low-level TLV parser on malformed BR Code data.
  class ParseError < Error
    # @return [Integer, nil] zero-based character offset of the problem
    attr_reader :position

    def initialize(message, position: nil)
      @position = position
      super(message)
    end
  end
end
