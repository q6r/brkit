# frozen_string_literal: true

require "json"

require_relative "problem"

module Brkit
  module API
    # Builds Rack response triples (+[status, headers, body]+) following Rack 3 conventions:
    # lower-case header names, a String body wrapped in an Array, +content-length+ set.
    module Response
      JSON_TYPE = "application/json"
      PROBLEM_TYPE = "application/problem+json"

      class << self
        # @param payload [Hash, Array] anything +JSON.generate+ accepts
        # @param status [Integer]
        # @param headers [Hash{String=>String}] extra headers (lower-case names)
        # @return [Array] a Rack response
        def json(payload, status: 200, headers: {})
          build(status, JSON_TYPE, JSON.generate(payload), headers)
        end

        # Renders a {Problem} as +application/problem+json+ (RFC 9457).
        #
        # @param problem [Problem]
        # @param request_id [String, nil] echoed in the document
        # @return [Array] a Rack response
        def problem(problem, request_id: nil)
          build(problem.status, PROBLEM_TYPE, JSON.generate(problem.to_h(request_id: request_id)), problem.headers)
        end

        # A response without content (204, 304); +content-type+ and +content-length+ must not be sent.
        #
        # @return [Array] a Rack response
        def bare(status, headers = {})
          [status, headers.dup, []]
        end

        # @param status [Integer]
        # @param content_type [String]
        # @param body [String]
        # @param headers [Hash{String=>String}] merged over the defaults
        # @return [Array] a Rack response
        def build(status, content_type, body, headers = {})
          defaults = { "content-type" => content_type, "content-length" => body.bytesize.to_s,
                       "cache-control" => "no-store" }
          [status, defaults.merge(headers), [body]]
        end

        # The same response without its body, as HEAD requires; the headers (including +content-length+) stay.
        #
        # @param response [Array] a Rack response
        # @return [Array]
        def without_body(response)
          status, headers, = response
          [status, headers, []]
        end
      end
    end
  end
end
