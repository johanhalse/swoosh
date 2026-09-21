# frozen_string_literal: true

require "test_helper"
require "json"

class SwooshTest < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil ::Swoosh::VERSION
  end

  def test_generate_payment_delegates_to_the_configured_client
    Swoosh.client = FakeClient.new

    assert_equal "ok", Swoosh.generate_payment(100, message: "Kaffe")
    assert_equal [100, { message: "Kaffe" }], Swoosh.client.calls.first
  ensure
    Swoosh.client = nil
  end

  class FakeClient
    attr_reader :calls

    def initialize
      @calls = []
    end

    def generate_payment(amount, **options)
      @calls << [amount, options]
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
    data = @main.data(100, message: "Kaffe")

    assert_equal 100, data[:amount]
    assert_equal "Kaffe", data[:message]
    assert_equal "SEK", data[:currency]
  end

  def test_environment_is_exposed
    assert_equal :test, @main.environment
  end
end

class SwooshPaymentRequestTest < Minitest::Test
  def test_the_merchant_number_comes_from_configuration
    assert_equal Swoosh::TestCerts::PAYEE_ALIAS, payload(100)[:payeeAlias]
  end

  def test_a_call_can_override_the_configured_merchant_number
    assert_equal "9876543210", payload(100, payee_alias: "9876543210")[:payeeAlias]
  end

  def test_a_configured_merchant_number_is_required_when_the_call_omits_one
    error = assert_raises(Swoosh::ConfigurationError) { bare_payload(100, callback_url: "https://x.test/cb") }

    assert_match "payee_alias", error.message
  end

  def test_the_callback_url_is_per_call
    assert_equal "https://shop.test/swish/subscriptions",
                 payload(100, callback_url: "https://shop.test/swish/subscriptions")[:callbackUrl]
  end

  def test_the_callback_url_falls_back_to_configuration_when_one_is_set
    assert_equal Swoosh::TestCerts::CALLBACK_URL, payload(100)[:callbackUrl]
  end

  def test_a_callback_url_is_required_when_nothing_configures_one
    error = assert_raises(Swoosh::ConfigurationError) { bare_payload(100, payee_alias: "1231181189") }

    assert_match "callback_url", error.message
  end

  def test_two_payment_types_can_use_different_callbacks_on_one_configuration
    main = Swoosh::TestCerts.client

    assert_equal "https://shop.test/orders", main.data(100, callback_url: "https://shop.test/orders")[:callbackUrl]
    assert_equal "https://shop.test/donations", main.data(100, callback_url: "https://shop.test/donations")[:callbackUrl]
  end

  def test_it_carries_the_optional_swish_fields_when_given
    data = payload(
      100,
      payer_alias: Swoosh::TestCerts::PAYER_ALIAS,
      payee_payment_reference: "order-42",
      age_limit: 18
    )

    assert_equal Swoosh::TestCerts::PAYER_ALIAS, data[:payerAlias]
    assert_equal "order-42", data[:payeePaymentReference]
    assert_equal 18, data[:ageLimit]
  end

  def test_it_omits_optional_fields_rather_than_sending_null
    data = payload(100)

    refute_includes data.keys, :payerAlias
    refute_includes data.keys, :payeePaymentReference
    refute_includes data.keys, :message
  end

  def test_currency_defaults_to_sek_and_is_overridable
    assert_equal "SEK", payload(100)[:currency]
    assert_equal "EUR", payload(100, currency: "EUR")[:currency]
  end

  private

  def payload(amount, **options)
    Swoosh::TestCerts.client.data(amount, **options)
  end

  def bare_payload(amount, **options)
    Swoosh::PaymentRequest.new(
      configuration: Swoosh::TestCerts.bare_configuration, amount: amount, **options
    ).to_h
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
    VCR.use_cassette("create_payment") { @main.generate_payment(100, message: "Kaffe") }

    assert_requested :put, PAYMENT_REQUEST_URI
  end

  def test_it_sends_the_swish_payment_payload_as_json
    VCR.use_cassette("create_payment") { @main.generate_payment(100, message: "Kaffe") }

    assert_requested(:put, PAYMENT_REQUEST_URI) do |request|
      payload = JSON.parse(request.body)

      payload["amount"] == 100 &&
        payload["currency"] == "SEK" &&
        payload["message"] == "Kaffe" &&
        payload["payeeAlias"] == "1231181189"
    end
  end

  def test_it_asks_for_a_json_response
    VCR.use_cassette("create_payment") { @main.generate_payment(100, message: "Kaffe") }

    assert_requested(:put, PAYMENT_REQUEST_URI) do |request|
      request.headers["Accept"] == "application/json"
    end
  end

  def test_swish_creates_the_payment_and_returns_its_location
    response = VCR.use_cassette("create_payment") do
      HTTP.headers(accept: "application/json")
          .put("#{@main.url}/#{@main.uuid}", ssl_context: @main.ssl_context, json: @main.data(100, message: "Kaffe"))
    end

    assert_equal 201, response.status.code
    assert_match %r{/api/v1/paymentrequests/[0-9A-F]{32}\z}, response.headers["Location"]
  end

  def test_generate_payment_returns_a_payment_carrying_the_id_we_generated
    payment = VCR.use_cassette("create_payment") { @main.generate_payment(100, message: "Kaffe") }

    assert_match(/\A[0-9A-F]{32}\z/, payment.id)
    assert_equal Swoosh::Payment::CREATED, payment.status
    assert_predicate payment, :pending?
  end

  def test_the_id_it_returns_is_the_one_it_sent
    payment = VCR.use_cassette("create_payment") { @main.generate_payment(100, message: "Kaffe") }

    assert_requested(:put, %r{/api/v2/paymentrequests/}) do |request|
      request.uri.path.end_with?(payment.id)
    end
  end
end

class SwooshMcommerceTest < Minitest::Test
  def setup
    @main = Swoosh::TestCerts.client
  end

  def test_omitting_the_payer_yields_a_token
    payment = create

    assert_predicate payment, :token?
    assert_match(/\A[0-9a-f]{32}\z/, payment.token)
  end

  def test_the_app_switch_url_carries_the_token_and_an_encoded_return_url
    url = create.app_switch_url(return_url: "https://shop.test/orders/1?a=b")

    assert_includes url, "swish://paymentrequest?token="
    assert_includes url, "callbackurl=https%3A%2F%2Fshop.test%2Forders%2F1%3Fa%3Db"
  end

  def test_the_qr_code_comes_back_as_image_bytes
    Swoosh::Test.stub_qr_code(body: "\x89PNG\r\n\x1a\nstub")
    qr = create.qr_code(size: 300)

    assert_equal "\x89PNG\r\n\x1a\nstub", qr
  end

  def test_an_ecommerce_payment_has_no_token_and_says_so_clearly
    payment = Swoosh::Payment.new({ "id" => "X" })
    error = assert_raises(Swoosh::Error) { payment.app_switch_url(return_url: "https://shop.test") }

    assert_match "payer_alias", error.message
  end

  private

  def create
    VCR.use_cassette("create_payment_mcommerce") do
      @main.generate_payment(199, callback_url: "https://example.com/cb", payee_payment_reference: "ABC123")
    end
  end
end

class SwooshFindPaymentTest < Minitest::Test
  def setup
    @main = Swoosh::TestCerts.client
  end

  def test_it_polls_swish_and_returns_the_payment
    payment = VCR.use_cassette("find_payment") { @main.find_payment("F5E4E0A2F9CE4B4EB6C45C0A8E9D0F1A") }

    assert_equal "CREATED", payment.status
    assert_equal "ABC123", payment.payee_payment_reference
    assert_in_delta 199.0, payment.amount
  end

  def test_it_reads_from_the_v1_endpoint
    VCR.use_cassette("find_payment") { @main.find_payment("F5E4E0A2F9CE4B4EB6C45C0A8E9D0F1A") }

    assert_requested :get, %r{/api/v1/paymentrequests/}
  end
end

class SwooshErrorTest < Minitest::Test
  def setup
    @main = Swoosh::TestCerts.client
  end

  def test_an_invalid_request_raises_with_the_swish_error_code
    error = assert_raises(Swoosh::RequestError) do
      VCR.use_cassette("create_payment_invalid") do
        @main.generate_payment(50, callback_url: "https://example.com/cb", payer_alias: "nope")
      end
    end

    assert_equal 422, error.status
    assert_equal "BE18", error.error_code
    assert_equal "Payer alias is invalid", error.error_message
  end

  def test_the_message_names_the_status_and_the_swish_error
    error = assert_raises(Swoosh::RequestError) do
      VCR.use_cassette("create_payment_invalid") do
        @main.generate_payment(50, callback_url: "https://example.com/cb", payer_alias: "nope")
      end
    end

    assert_match "422", error.message
    assert_match "BE18", error.message
  end

  def test_an_unknown_payment_raises_payment_not_found
    WebMock.stub_request(:get, %r{/api/v1/paymentrequests/})
           .to_return(status: 404, body: %([{"errorCode":"RP04","errorMessage":"No payment request found"}]))

    error = assert_raises(Swoosh::PaymentNotFound) { @main.find_payment("3D265CCC2CBA48E49026181441E1DADB") }

    assert_equal "RP04", error.error_code
  end

  # A sweep retries transient failures but not this one, so it has to be able to
  # tell them apart without matching on error codes.
  def test_payment_not_found_is_a_request_error_but_not_every_request_error
    assert_operator Swoosh::PaymentNotFound, :<, Swoosh::RequestError

    WebMock.stub_request(:get, %r{/api/v1/paymentrequests/})
           .to_return(status: 422, body: %([{"errorCode":"PA01","errorMessage":"Parameter is not correct."}]))

    assert_raises(Swoosh::RequestError) { @main.find_payment("NOTAVALIDUUID") }
    refute_raises_payment_not_found { @main.find_payment("NOTAVALIDUUID") }
  end

  def test_a_server_error_is_distinguishable_from_a_request_error
    assert_operator Swoosh::ServerError, :<, Swoosh::ResponseError
    assert_operator Swoosh::RequestError, :<, Swoosh::ResponseError
  end

  def refute_raises_payment_not_found
    yield
  rescue Swoosh::PaymentNotFound
    flunk "expected not to raise Swoosh::PaymentNotFound"
  rescue Swoosh::RequestError
    pass
  end

  def test_a_non_json_body_still_produces_a_usable_error
    error = Swoosh::ResponseError.new(status: 503, body: "<html>nope</html>")

    assert_equal 503, error.status
    assert_empty error.errors
    assert_match "503", error.message
  end
end
