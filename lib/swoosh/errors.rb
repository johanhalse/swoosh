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

    # Builds the most specific error the response justifies. Swish reports
    # several quite different problems as the same 422, so status alone is not
    # enough to pick a class -- the errorCode in the body decides.
    def self.for(status:, body:)
      subclass_for(status, body).new(status: status, body: body)
    end

    def self.subclass_for(status, body)
      return ServerError if status >= 500
      return PaymentNotFound if status == 404

      ERROR_CLASSES_BY_CODE.fetch(error_code_in(body), RequestError)
    end

    def self.error_code_in(body)
      parsed = JSON.parse(body.to_s)
      parsed = parsed.first if parsed.is_a?(Array)
      parsed["errorCode"] if parsed.is_a?(Hash)
    rescue JSON::ParserError
      nil
    end

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

  # 404 -- Swish has no such payment *for this certificate*. Per the integration
  # guide it means "not found, or it was not created by the merchant", so it is
  # not proof the payment doesn't exist: the same 404 comes back for a real,
  # possibly paid payment polled with the wrong merchant certificate.
  #
  # Retrying won't help, but treating one as "this payment never happened" is
  # only safe once you know the certificate is right. In bulk, this almost
  # always means a configuration mismatch rather than N missing payments.
  class PaymentNotFound < RequestError; end

  # 422 RP07 -- the payment is no longer CREATED, so there is nothing to
  # withdraw. This is the race worth designing for rather than an edge case: the
  # payer accepted somewhere between your decision to cancel and the PATCH
  # landing, which on a checkout page people abandon by paying is common.
  #
  # The payment may well be PAID, so a failed cancel is never licence to treat
  # the order as abandoned. Poll before you decide anything.
  class PaymentNotCancellable < RequestError; end

  # 422 RP08 -- already cancelled. The state you asked for already holds, so
  # this is the one cancel failure that is usually safe to rescue and ignore.
  class PaymentAlreadyCancelled < RequestError; end

  # 5xx -- Swish had a problem. Worth retrying.
  class ServerError < ResponseError; end

  # Declared once the classes exist, so the mapping reads as a single table.
  # An unrecognised code falls back to RequestError rather than raising, so a
  # code Swish adds later degrades to something still rescuable.
  ERROR_CLASSES_BY_CODE = {
    "RP07" => PaymentNotCancellable,
    "RP08" => PaymentAlreadyCancelled
  }.freeze
end
