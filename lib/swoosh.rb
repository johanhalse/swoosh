# frozen_string_literal: true

require "http"
require "securerandom"
require_relative "swoosh/version"
require_relative "swoosh/railtie" if defined? ::Rails::Railtie

module Swoosh
  class Error < StandardError; end

  def self.client=(client)
    @client = client
  end

  def self.client
    @client
  end

  def self.generate_payment(amount, message)
    client.generate_payment(amount, message)
  end

  class Main
    TEST_URL = "https://mss.cpc.getswish.net/swish-cpcapi/api/v2/paymentrequests/"
    PRODUCTION_URL = "https://cpc.getswish.net/swish-cpcapi/api/v2/paymentrequests/"

    def initialize(env:)
      @env = env
      @url = @env == "production" ? PRODUCTION_URL : TEST_URL

      @cert, @root_cert = load_certificates
    end

    def load_certificates
      [
        OpenSSL::PKCS12.new(File.read(cert_path("swish_merchant_certificate_#{@env}.p12")), "swish"),
        OpenSSL::X509::Certificate.new(File.read(cert_path("Swish_TLS_RootCA.pem")))
      ]
    end

    def cert_path(file)
      File.absolute_path("./config/certs/#{file}")
    end

    def generate_payment(amount)
      HTTP
        .headers(accept: "application/json")
        .put("#{@url}/#{uuid}", ssl_context: ssl_context, json: data(amount, message)).to_s
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

    def ssl_context
      OpenSSL::SSL::SSLContext.new.tap do |ctx|
        ctx.add_certificate(
          @cert.certificate,
          @cert.key,
          @cert.ca_certs.push(@root_cert)
        )
      end
    end

    def read_file(file)
      File.read(file)
    end

    def client
      @client ||= Client.new(@cert, @private_key, @root_cert)
    end
  end
end
