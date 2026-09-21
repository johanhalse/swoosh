# frozen_string_literal: true

require_relative "rails_helper"

class SwooshRailtieTest < ActiveSupport::TestCase
  test "the dummy application boots with swoosh configured" do
    assert_kind_of Swoosh::Configuration, Swoosh.configuration
  end

  test "config.swoosh is available to the host application" do
    assert_respond_to Rails.application.config, :swoosh
  end

  test "the test environment talks to the swish staging playground" do
    assert_equal :test, Swoosh.configuration.environment
    assert_equal Swoosh::Main::TEST_URL, Swoosh.client.url
  end

  test "cert_dir defaults to the application's config/certs" do
    assert_equal Rails.root.join("config/certs").to_s, Swoosh.configuration.cert_dir.to_s
  end

  test "development defaults to staging so it never reaches real money" do
    with_rails_env("development") do |config|
      assert_equal :test, config.environment
      assert_equal Swoosh::Main::TEST_URL, Swoosh.client.url
    end
  end

  test "production defaults to the production environment" do
    with_rails_env("production") do |config|
      assert_equal :production, config.environment
      assert_equal Swoosh::Main::PRODUCTION_URL, Swoosh.client.url
    end
  end

  test "an app can switch development over to production certificates" do
    with_rails_env("development", environment: :production) do |config|
      assert_equal :production, config.environment
      assert_equal Swoosh::Main::PRODUCTION_URL, Swoosh.client.url
    end
  end

  test "staging is accepted as an alias in app config" do
    with_rails_env("development", environment: :staging) do |config|
      assert_equal :test, config.environment
    end
  end

  test "an app can point cert_dir somewhere else" do
    Dir.mktmpdir do |dir|
      with_rails_env("development", cert_dir: dir) do |config|
        assert_equal dir, config.cert_dir.to_s
      end
    end
  end

  test "an app can override the certificate password" do
    with_rails_env("development", cert_password: "hunter2") do |config|
      assert_equal "hunter2", config.cert_password
    end
  end

  test "an unknown environment fails the boot with a helpful message" do
    error = assert_raises(Swoosh::ConfigurationError) do
      with_rails_env("development", environment: :sandbox) { nil }
    end

    assert_match "sandbox", error.message
  end
end

class SwooshRailsCertificateTest < ActiveSupport::TestCase
  test "a fresh app with an empty config/certs uses the bundled staging bundle" do
    assert_equal Swoosh::Certificates::BUNDLED_TEST_CERT, Swoosh.client.certificates.cert_path
  end

  test "dropping swish_test.p12 into config/certs takes precedence" do
    Dir.mktmpdir do |dir|
      drop_in_certificate(dir, :test)

      with_rails_env("development", cert_dir: dir) do
        assert_equal File.join(dir, "swish_test.p12"), Swoosh.client.certificates.cert_path
        assert_kind_of OpenSSL::X509::Certificate, Swoosh.client.cert.certificate
      end
    end
  end

  test "dropping swish_production.p12 into config/certs is picked up in production" do
    Dir.mktmpdir do |dir|
      drop_in_certificate(dir, :production)

      with_rails_env("production", cert_dir: dir) do
        assert_equal File.join(dir, "swish_production.p12"), Swoosh.client.certificates.cert_path
        assert_kind_of OpenSSL::X509::Certificate, Swoosh.client.cert.certificate
      end
    end
  end

  test "a production app without a certificate says where it looked" do
    Dir.mktmpdir do |dir|
      with_rails_env("production", cert_dir: dir) do
        error = assert_raises(Swoosh::CertificateError) { Swoosh.client.certificates.cert_path }

        assert_match "swish_production.p12", error.message
        assert_match dir, error.message
      end
    end
  end
end
