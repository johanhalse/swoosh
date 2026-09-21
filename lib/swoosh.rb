# frozen_string_literal: true

require "http"
require "openssl"
require "securerandom"
require_relative "swoosh/version"
require_relative "swoosh/railtie" if defined? Rails::Railtie

module Swoosh
  class Error < StandardError; end

  class << self
    attr_accessor :client
  end

  def self.generate_payment(amount, message)
    client.generate_payment(amount, message)
  end

  class Main
    TEST_URL = "https://mss.cpc.getswish.net/swish-cpcapi/api/v2/paymentrequests"
    PRODUCTION_URL = "https://cpc.getswish.net/swish-cpcapi/api/v2/paymentrequests"
    DEFAULT_CERT_DIR = "./config/certs"
    ROOT_CA_FILE = "Swish_TLS_RootCA.pem"

    attr_reader :env, :url

    def initialize(env:, cert_dir: DEFAULT_CERT_DIR, cert_file: nil, cert_password: "swish")
      @env = env
      @url = @env == "production" ? PRODUCTION_URL : TEST_URL
      @cert_dir = cert_dir
      @cert_file = cert_file || "swish_merchant_certificate_#{@env}.p12"
      @cert_password = cert_password
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
      @cert ||= OpenSSL::PKCS12.new(File.read(cert_path(@cert_file)), @cert_password)
    end

    def root_cert
      @root_cert ||= OpenSSL::X509::Certificate.new(File.read(cert_path(ROOT_CA_FILE)))
    end

    def ssl_context
      OpenSSL::SSL::SSLContext.new.tap do |ctx|
        ctx.add_certificate(
          cert.certificate,
          cert.key,
          cert.ca_certs.push(root_cert)
        )
      end
    end

    def cert_path(file)
      File.absolute_path(File.join(@cert_dir, file))
    end
  end
end
