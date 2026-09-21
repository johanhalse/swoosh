# frozen_string_literal: true

require "json"
require "net/http"
require "openssl"
require "securerandom"
require "uri"
require_relative "swoosh/version"
require_relative "swoosh/errors"
require_relative "swoosh/configuration"
require_relative "swoosh/certificates"
require_relative "swoosh/payment"
require_relative "swoosh/payment_request"
require_relative "swoosh/token_store"
require_relative "swoosh/qr_code"
require_relative "swoosh/callback"
require_relative "swoosh/railtie" if defined? Rails::Railtie

module Swoosh
  class << self
    attr_writer :client

    def configuration
      @configuration ||= Configuration.new
    end

    # Swoosh.configure { |c| c.environment = :production }
    def configure
      yield configuration
      @client = nil
      configuration
    end

    def client
      @client ||= Main.new(configuration: configuration)
    end

    def reset!
      @configuration = nil
      @client = nil
    end

    def generate_payment(amount, **options)
      client.generate_payment(amount, **options)
    end

    def find_payment(id)
      client.find_payment(id)
    end

    def cancel_payment(id)
      client.cancel_payment(id)
    end

    def token_for(payment_id)
      client.token_for(payment_id)
    end
  end

  class Main
    TEST_URL = "https://mss.cpc.getswish.net/swish-cpcapi/api/v2/paymentrequests"
    PRODUCTION_URL = "https://cpc.getswish.net/swish-cpcapi/api/v2/paymentrequests"

    # Creating a payment is v2 (we supply the id); reading one back is v1.
    TEST_LOOKUP_URL = "https://mss.cpc.getswish.net/swish-cpcapi/api/v1/paymentrequests"
    PRODUCTION_LOOKUP_URL = "https://cpc.getswish.net/swish-cpcapi/api/v1/paymentrequests"

    JSON_CONTENT_TYPE = "application/json"

    # Cancelling is a JSON Patch against the payment's status, not a body of its
    # own, and Swish rejects it with a 415 under any other content type.
    JSON_PATCH_CONTENT_TYPE = "application/json-patch+json"
    CANCEL_PATCH = [{ op: "replace", path: "/status", value: "cancelled" }].freeze

    REQUEST_CLASSES = {
      get: Net::HTTP::Get,
      put: Net::HTTP::Put,
      patch: Net::HTTP::Patch
    }.freeze

    attr_reader :configuration, :certificates, :token_store

    def initialize(configuration: Swoosh.configuration)
      @configuration = configuration
      @certificates = Certificates.new(configuration)
      @token_store = TokenStore.new(configuration.token_store, ttl: configuration.token_ttl)
    end

    def environment = configuration.environment
    def url = configuration.production? ? PRODUCTION_URL : TEST_URL
    def lookup_url = configuration.production? ? PRODUCTION_LOOKUP_URL : TEST_LOOKUP_URL

    # Swoosh.generate_payment(100, callback_url: "https://example.com/swish")
    #
    # Omit payer_alias for the Swish-app (m-commerce) flow and the payment comes
    # back carrying a token; supply one and Swish notifies that number instead.
    def generate_payment(amount, **options)
      id = uuid
      response = request(:put, "#{url}/#{id}", body: JSON.generate(data(amount, **options)))
      # Net::HTTP matches header names case-insensitively, which matters: Swish
      # sends this back as "Paymentrequesttoken".
      token = response["PaymentRequestToken"]
      token_store.write(id, token)

      Payment.new({ "id" => id, "status" => Payment::CREATED }, token: token)
    end

    def find_payment(id)
      Payment.from_json(request(:get, "#{lookup_url}/#{id}").body.to_s)
    end

    # Withdraws a payment request the payer hasn't answered yet, so an abandoned
    # checkout stops waiting out the full three minutes.
    #
    # Only a CREATED payment can be cancelled, so expect the race: the payer
    # accepts between your decision to cancel and this request arriving. Swish
    # reports that as PaymentNotCancellable and a second cancel as
    # PaymentAlreadyCancelled -- believe find_payment over your own assumption
    # about which state the payment was in.
    def cancel_payment(id)
      response = request(
        :patch, "#{lookup_url}/#{id}",
        body: JSON.generate(CANCEL_PATCH),
        content_type: JSON_PATCH_CONTENT_TYPE
      )
      # The token dies with the request; keeping it would let token_for hand back
      # something that still renders a QR nobody can pay.
      token_store.delete(id)

      Payment.from_json(response.body.to_s)
    end

    # The token stored when the payment was created, or nil. Nil means "create a
    # fresh payment request" -- never an error.
    def token_for(payment_id) = token_store.read(payment_id)

    def data(amount, **options)
      PaymentRequest.new(configuration: configuration, amount: amount, **options).to_h
    end

    def uuid = SecureRandom.uuid.delete("-").upcase

    def cert = certificates.cert
    def root_cert = certificates.root_ca

    # A connection carrying the merchant certificate, ready to issue one
    # request. Net::HTTP opens and closes it around #request on its own.
    def connection(uri)
      certificates.configure_ssl(Net::HTTP.new(uri.host, uri.port))
    end

    private

    def request(verb, target, body: nil, content_type: JSON_CONTENT_TYPE)
      uri = URI.parse(target)
      response = connection(uri).request(build_request(verb, uri, body, content_type))
      return response if response.is_a?(Net::HTTPSuccess)

      raise ResponseError.for(status: response.code.to_i, body: response.body.to_s)
    end

    def build_request(verb, uri, body, content_type)
      REQUEST_CLASSES.fetch(verb).new(uri).tap do |request|
        request["Accept"] = JSON_CONTENT_TYPE
        next if body.nil?

        request["Content-Type"] = content_type
        request.body = body
      end
    end
  end
end
