# frozen_string_literal: true

require "http"
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
      response = request(:put, "#{url}/#{id}", json: data(amount, **options))
      token = response.headers["PaymentRequestToken"]
      token_store.write(id, token)

      Payment.new({ "id" => id, "status" => Payment::CREATED }, token: token)
    end

    def find_payment(id)
      Payment.from_json(request(:get, "#{lookup_url}/#{id}").to_s)
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
    def ssl_context = certificates.ssl_context

    private

    def error_class(response)
      return ServerError if response.status.server_error?
      return PaymentNotFound if response.status.code == 404

      RequestError
    end

    def request(verb, target, **options)
      response = HTTP.headers(accept: "application/json")
                     .public_send(verb, target, ssl_context: ssl_context, **options)
      return response if response.status.success?

      raise error_class(response).new(status: response.status.code, body: response.to_s)
    end
  end
end
