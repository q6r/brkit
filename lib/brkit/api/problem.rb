# frozen_string_literal: true

require_relative "../errors"
require_relative "../result"

module Brkit
  module API
    # An HTTP error described as an RFC 9457 "problem details" document (+application/problem+json+).
    #
    # Handlers and middleware raise a Problem; {Middleware::ErrorBoundary} turns it into a response.
    # Each kind has a stable slug that is part of the +type+ URI and documented in docs/problems.md.
    class Problem < Brkit::Error
      BASE_URI = "https://github.com/q6r/brkit/blob/main/docs/problems.md#"

      # slug => [status, title]
      CATALOG = {
        "bad-request" => [400, "Bad request"],
        "invalid-parameter" => [400, "Invalid parameter"],
        "invalid-json" => [400, "Invalid JSON body"],
        "not-found" => [404, "Not found"],
        "method-not-allowed" => [405, "Method not allowed"],
        "not-acceptable" => [406, "Not acceptable"],
        "payload-too-large" => [413, "Payload too large"],
        "uri-too-long" => [414, "URI too long"],
        "unsupported-media-type" => [415, "Unsupported media type"],
        "validation-error" => [422, "Validation error"],
        "rate-limited" => [429, "Too many requests"],
        "internal-error" => [500, "Internal server error"]
      }.freeze

      # @return [String] key into {CATALOG}
      attr_reader :slug
      # @return [Integer] HTTP status
      attr_reader :status
      # @return [String] short, stable summary of the problem type
      attr_reader :title
      # @return [String, nil] explanation specific to this occurrence
      attr_reader :detail
      # @return [Array<Issue>, nil] field-level problems
      attr_reader :errors
      # @return [Hash{String=>String}] extra response headers (+allow+, +retry-after+, ...)
      attr_reader :headers

      # @param slug [String] a key of {CATALOG}
      # @param detail [String, nil]
      # @param errors [Array<Issue>, nil]
      # @param headers [Hash{String=>String}] lower-case header names
      def initialize(slug, detail = nil, errors: nil, headers: {})
        @slug = slug
        @status, @title = CATALOG.fetch(slug)
        @detail = detail
        @errors = errors&.freeze
        @headers = headers.freeze
        super(detail || @title)
      end

      # @param request_id [String, nil] value of the +x-request-id+ header, echoed as an extension member
      # @return [Hash{Symbol=>Object}] the JSON document
      def to_h(request_id: nil)
        { type: "#{BASE_URI}#{slug}", title: title, status: status, detail: detail, request_id: request_id,
          errors: errors&.map(&:to_h) }.compact
      end

      class << self
        # @param allowed [Array<String>] methods the resource supports
        def method_not_allowed(method, allowed)
          new("method-not-allowed", "#{method} is not supported here; use #{allowed.join(', ')}",
              headers: { "allow" => allowed.join(", ") })
        end

        # @param limit [Integer] maximum body size in bytes
        def payload_too_large(limit)
          new("payload-too-large", "the request body is larger than #{limit} bytes")
        end

        # @param retry_after [Integer] seconds until a token is available
        # @param headers [Hash{String=>String}] rate-limit headers to send along
        def rate_limited(retry_after, headers)
          new("rate-limited", "rate limit exceeded; retry in #{retry_after} s",
              headers: headers.merge("retry-after" => retry_after.to_s))
        end

        # @param issues [Array<Issue>]
        def validation(issues)
          new("validation-error", issues.length == 1 ? issues.first.message : "#{issues.length} fields are invalid",
              errors: issues)
        end

        # @param issues [Array<Issue>]
        def invalid_parameter(issues)
          new("invalid-parameter", issues.length == 1 ? issues.first.message : "#{issues.length} parameters are invalid",
              errors: issues)
        end
      end
    end
  end
end
