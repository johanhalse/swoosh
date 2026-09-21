# frozen_string_literal: true

require "json"

module Swoosh
  class Error < StandardError; end
  class ConfigurationError < Error; end
  class CertificateError < Error; end

  # Swish answered, but not with success. A 422 carries a JSON array of
  # {errorCode, errorMessage, additionalInformation}; other statuses may not.
  class ResponseError < Error
    attr_reader :status, :errors, :body

    def initialize(status:, body:)
      @status = status
      @body = body
      @errors = parse(body)
      super(build_message)
    end

    def error_code = errors.first&.fetch("errorCode", nil)
    def error_message = errors.first&.fetch("errorMessage", nil)

    private

    def parse(body)
      parsed = JSON.parse(body.to_s)
      parsed.is_a?(Array) ? parsed : [parsed]
    rescue JSON::ParserError
      []
    end

    def build_message
      return "Swish responded #{status}: #{body.to_s[0, 200]}" if errors.empty?

      described = errors.map { |e| "#{e["errorCode"]} #{e["errorMessage"]}".strip }.join(", ")
      "Swish responded #{status}: #{described}"
    end
  end

  # 4xx -- the request was wrong. A bug, or a payer number that can't be used.
  class RequestError < ResponseError; end

  # 5xx -- Swish had a problem. Worth retrying.
  class ServerError < ResponseError; end
end
