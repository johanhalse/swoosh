# frozen_string_literal: true

require "http"
require "openssl"
require "securerandom"
require_relative "swoosh/version"
require_relative "swoosh/configuration"
require_relative "swoosh/certificates"
require_relative "swoosh/railtie" if defined? Rails::Railtie

module Swoosh
  class Error < StandardError; end
  class ConfigurationError < Error; end
  class CertificateError < Error; end

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

    def generate_payment(amount, message)
      client.generate_payment(amount, message)
    end
  end

  class Main
    TEST_URL = "https://mss.cpc.getswish.net/swish-cpcapi/api/v2/paymentrequests"
    PRODUCTION_URL = "https://cpc.getswish.net/swish-cpcapi/api/v2/paymentrequests"

    attr_reader :configuration, :certificates

    def initialize(configuration: Swoosh.configuration)
      @configuration = configuration
      @certificates = Certificates.new(configuration)
    end

    def environment
      configuration.environment
    end

    def url
      configuration.production? ? PRODUCTION_URL : TEST_URL
    end

    def generate_payment(amount, message)
      HTTP
        .headers(accept: "application/json")
        .put("#{url}/#{uuid}", ssl_context: ssl_context, json: data(amount, message)).to_s
    end

    def data(amount, message)
      {
        payeePaymentReference: "0123456789",
        callbackUrl: "https://example.com/api/swishcb/paymentrequests",
        payerAlias: "4671234768",
        payeeAlias: "1231181189",
        amount: amount,
        currency: "SEK",
        message: message
      }
    end

    def uuid
      SecureRandom.uuid.delete("-").upcase
    end

    def cert
      certificates.cert
    end

    def root_cert
      certificates.root_ca
    end

    def ssl_context
      certificates.ssl_context
    end
  end
end
