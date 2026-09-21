# frozen_string_literal: true

require "test_helper"

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
    assert_equal Swoosh::Main::PRODUCTION_URL, Swoosh::TestCerts.client(env: "production").url
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

  def test_cert_path_joins_the_configured_cert_dir
    assert_equal File.join(Swoosh::TestCerts::DIR, "x.pem"), @main.cert_path("x.pem")
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
