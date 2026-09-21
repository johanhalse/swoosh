# frozen_string_literal: true

require "test_helper"
require "json"

class SwooshTest < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil ::Swoosh::VERSION
  end

  def test_generate_payment_delegates_to_the_configured_client
    Swoosh.client = FakeClient.new

    assert_equal "ok", Swoosh.generate_payment(100, "Kaffe")
    assert_equal [100, "Kaffe"], Swoosh.client.calls.first
  ensure
    Swoosh.client = nil
  end

  class FakeClient
    attr_reader :calls

    def initialize
      @calls = []
    end

    def generate_payment(amount, message)
      @calls << [amount, message]
      "ok"
    end
  end
end

class SwooshMainTest < Minitest::Test
  def setup
    @main = Swoosh::TestCerts.client
  end

  def test_test_environment_uses_the_mss_url
    assert_equal Swoosh::Main::TEST_URL, @main.url
  end

  def test_production_environment_uses_the_production_url
    assert_equal Swoosh::Main::PRODUCTION_URL, Swoosh::TestCerts.client(environment: :production, cert_dir: Swoosh::TestCerts::DIR).url
  end

  def test_uuid_is_an_uppercase_hex_string_without_dashes
    assert_match(/\A[0-9A-F]{32}\z/, @main.uuid)
  end

  def test_uuid_is_unique_per_call
    refute_equal @main.uuid, @main.uuid
  end

  def test_data_builds_a_swish_payment_payload
    data = @main.data(100, "Kaffe")

    assert_equal 100, data[:amount]
    assert_equal "Kaffe", data[:message]
    assert_equal "SEK", data[:currency]
  end

  def test_environment_is_exposed
    assert_equal :test, @main.environment
  end
end

class SwooshCertificateResolutionTest < Minitest::Test
  def test_it_looks_for_a_bundle_named_after_the_environment
    assert_equal "swish_test.p12", certificates(:test).filename
    assert_equal "swish_production.p12", certificates(:production).filename
  end

  def test_it_picks_up_a_bundle_dropped_into_the_cert_dir
    Swoosh::TestCerts.with_cert_dir(environment: :test) do |dir|
      certs = certificates(:test, cert_dir: dir)

      assert_equal File.join(dir, "swish_test.p12"), certs.cert_path
      assert_kind_of OpenSSL::X509::Certificate, certs.cert.certificate
    end
  end

  def test_a_dropped_in_bundle_wins_over_the_bundled_staging_certificate
    Swoosh::TestCerts.with_cert_dir(environment: :test) do |dir|
      refute_equal Swoosh::Certificates::BUNDLED_TEST_CERT, certificates(:test, cert_dir: dir).cert_path
    end
  end

  def test_staging_falls_back_to_the_certificates_bundled_with_the_gem
    assert_equal Swoosh::Certificates::BUNDLED_TEST_CERT, certificates(:test).cert_path
  end

  def test_staging_falls_back_even_when_the_cert_dir_is_empty
    Dir.mktmpdir do |dir|
      assert_equal Swoosh::Certificates::BUNDLED_TEST_CERT, certificates(:test, cert_dir: dir).cert_path
    end
  end

  def test_production_never_falls_back_to_the_bundled_staging_certificate
    Dir.mktmpdir do |dir|
      error = assert_raises(Swoosh::CertificateError) { certificates(:production, cert_dir: dir).cert_path }

      assert_match "swish_production.p12", error.message
      assert_match dir, error.message
    end
  end

  def test_production_reads_the_bundle_dropped_into_the_cert_dir
    Swoosh::TestCerts.with_cert_dir(environment: :production) do |dir|
      certs = certificates(:production, cert_dir: dir)

      assert_equal File.join(dir, "swish_production.p12"), certs.cert_path
      assert_kind_of OpenSSL::X509::Certificate, certs.cert.certificate
    end
  end

  def test_a_wrong_password_reports_the_path_it_tried
    Swoosh::TestCerts.with_cert_dir(environment: :test) do |dir|
      certs = certificates(:test, cert_dir: dir, cert_password: "nope")
      error = assert_raises(Swoosh::CertificateError) { certs.cert }

      assert_match "cert_password", error.message
    end
  end

  def test_the_root_ca_ships_with_the_gem_and_is_overridable
    assert_equal Swoosh::Certificates::BUNDLED_ROOT_CA, certificates(:test).root_ca_path
    assert_equal "/tmp/other.pem", certificates(:test, root_ca_path: "/tmp/other.pem").root_ca_path
  end

  private

  def certificates(environment, **attributes)
    Swoosh::Certificates.new(Swoosh::TestCerts.configuration(environment: environment, **attributes))
  end
end

class SwooshConfigurationTest < Minitest::Test
  def test_it_defaults_to_the_staging_environment
    assert_equal :test, Swoosh::Configuration.new.environment
  end

  def test_staging_is_an_alias_for_test
    assert_equal :test, Swoosh::TestCerts.configuration(environment: :staging).environment
  end

  def test_it_accepts_strings
    assert_equal :production, Swoosh::TestCerts.configuration(environment: "production").environment
  end

  def test_it_rejects_an_unknown_environment
    error = assert_raises(Swoosh::ConfigurationError) { Swoosh::Configuration.new.environment = :sandbox }

    assert_match "sandbox", error.message
  end
end

class SwooshCertificateTest < Minitest::Test
  def setup
    @main = Swoosh::TestCerts.client
  end

  def test_merchant_certificate_parses_with_modern_openssl
    assert_kind_of OpenSSL::X509::Certificate, @main.cert.certificate
    assert_kind_of OpenSSL::PKey::RSA, @main.cert.key
  end

  def test_root_ca_is_the_digicert_root_that_signs_the_swish_endpoints
    assert_equal "DigiCert Global Root G2", common_name(@main.root_cert)
  end

  def test_root_ca_is_not_expired
    assert_operator @main.root_cert.not_after, :>, Time.now
  end

  def test_merchant_certificate_is_not_expired
    assert_operator @main.cert.certificate.not_after, :>, Time.now
  end

  def test_merchant_private_key_matches_its_certificate
    assert @main.cert.certificate.check_private_key(@main.cert.key)
  end

  def test_merchant_certificate_ships_the_nordea_chain
    chain = @main.cert.ca_certs.map { |c| c.subject.to_a.assoc("CN")[1] }

    assert_includes chain, "Nordea Customer CA1 v2 for Swish"
    assert_includes chain, "Nordea Root CA v2 for Swish"
  end

  def test_ssl_context_is_built_from_the_certificate_chain
    assert_kind_of OpenSSL::SSL::SSLContext, @main.ssl_context
  end

  private

  def common_name(cert)
    cert.subject.to_a.assoc("CN")[1]
  end
end

class SwooshCreatePaymentTest < Minitest::Test
  PAYMENT_REQUEST_URI = %r{\Ahttps://mss\.cpc\.getswish\.net/swish-cpcapi/api/v2/paymentrequests/[0-9A-F]{32}\z}

  def setup
    @main = Swoosh::TestCerts.client
  end

  def test_it_puts_the_payment_to_a_freshly_generated_instruction_id
    VCR.use_cassette("create_payment") { @main.generate_payment(100, "Kaffe") }

    assert_requested :put, PAYMENT_REQUEST_URI
  end

  def test_it_sends_the_swish_payment_payload_as_json
    VCR.use_cassette("create_payment") { @main.generate_payment(100, "Kaffe") }

    assert_requested(:put, PAYMENT_REQUEST_URI) do |request|
      payload = JSON.parse(request.body)

      payload["amount"] == 100 &&
        payload["currency"] == "SEK" &&
        payload["message"] == "Kaffe" &&
        payload["payeeAlias"] == "1231181189"
    end
  end

  def test_it_asks_for_a_json_response
    VCR.use_cassette("create_payment") { @main.generate_payment(100, "Kaffe") }

    assert_requested(:put, PAYMENT_REQUEST_URI) do |request|
      request.headers["Accept"] == "application/json"
    end
  end

  def test_swish_creates_the_payment_and_returns_its_location
    response = VCR.use_cassette("create_payment") do
      HTTP.headers(accept: "application/json")
          .put("#{@main.url}/#{@main.uuid}", ssl_context: @main.ssl_context, json: @main.data(100, "Kaffe"))
    end

    assert_equal 201, response.status.code
    assert_match %r{/api/v1/paymentrequests/[0-9A-F]{32}\z}, response.headers["Location"]
  end

  # Swish answers 201 with an empty body: the instruction id only comes back in
  # the Location header, so the current return value carries nothing.
  def test_generate_payment_returns_the_empty_response_body
    body = VCR.use_cassette("create_payment") { @main.generate_payment(100, "Kaffe") }

    assert_empty body
  end
end
