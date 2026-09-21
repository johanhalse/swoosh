# frozen_string_literal: true

require "openssl"

module Swoosh
  # Resolves and loads the certificates for one environment.
  #
  # Drop your bank-issued bundle into the configured directory named after the
  # environment it belongs to:
  #
  #   config/certs/swish_production.p12
  #   config/certs/swish_test.p12
  #
  # In :test we fall back to the Swish test certificates bundled with the gem,
  # so a fresh app can talk to the Swish staging playground with no setup at
  # all. :production never falls back -- a missing bundle there is an error.
  class Certificates
    BUNDLED_DIR = File.expand_path("../../certs", __dir__)
    BUNDLED_TEST_CERT = File.join(BUNDLED_DIR, "Swish_Merchant_TestCertificate_1234679304.p12")
    BUNDLED_ROOT_CA = File.join(BUNDLED_DIR, "Swish_TLS_RootCA.pem")

    def initialize(configuration)
      @configuration = configuration
    end

    def cert
      @cert ||= OpenSSL::PKCS12.new(File.read(cert_path), @configuration.cert_password)
    rescue OpenSSL::PKCS12::PKCS12Error => e
      raise CertificateError, "Could not open #{cert_path} (wrong cert_password?): #{e.message}"
    end

    def root_ca
      @root_ca ||= OpenSSL::X509::Certificate.new(File.read(root_ca_path))
    end

    # Net::HTTP builds its own SSL context internally rather than accepting one,
    # so the pieces go onto the connection:
    #
    #   cert / key       the merchant certificate Swish authenticates us by
    #   extra_chain_cert the Nordea intermediates that vouch for it, which Swish
    #                    needs because it does not hold them itself
    #   ca_file          the root we verify *Swish* by -- the other direction
    #
    # Both directions matter. Sending the merchant credential to whatever
    # answers on the far end, unverified, would be worse than not sending it.
    def configure_ssl(http)
      http.use_ssl = true
      http.cert = cert.certificate
      http.key = cert.key
      http.extra_chain_cert = cert.ca_certs
      http.ca_file = root_ca_path
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      http
    end

    # <cert_dir>/swish_test.p12 or <cert_dir>/swish_production.p12
    def filename
      "swish_#{@configuration.environment}.p12"
    end

    def cert_path
      @cert_path ||= resolve_cert_path
    end

    def root_ca_path
      @configuration.root_ca_path&.to_s || BUNDLED_ROOT_CA
    end

    private

    def resolve_cert_path
      configured = configured_cert_path

      return configured if configured && File.exist?(configured)
      return BUNDLED_TEST_CERT unless @configuration.production?

      raise CertificateError, missing_certificate_message(configured)
    end

    def configured_cert_path
      dir = @configuration.cert_dir
      File.join(dir.to_s, filename) if dir
    end

    def missing_certificate_message(configured)
      return "No Swish production certificate found: set `cert_dir` and place #{filename} in it." unless configured

      "No Swish production certificate at #{configured}. Place your bank-issued bundle there, " \
        "or point `cert_dir` somewhere else."
    end
  end
end
