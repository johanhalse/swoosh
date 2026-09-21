# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "swoosh"

require "minitest/autorun"
require "fileutils"
require "tmpdir"
require "webmock/minitest"
require "swoosh/test"

require_relative "support/vcr"

module Swoosh
  module TestCerts
    DIR = File.expand_path("../certs", __dir__)
    MERCHANT = "Swish_Merchant_TestCertificate_1234679304.p12"

    # A client on the staging certificates bundled with the gem. Passing no
    # cert_dir is exactly what a fresh app does, so this exercises the fallback.
    def self.client(environment: :test, **attributes)
      Swoosh::Main.new(configuration: configuration(environment: environment, **attributes))
    end

    # The merchant number and callback Swish's own staging examples use.
    PAYEE_ALIAS = "1231181189"
    CALLBACK_URL = "https://example.com/api/swishcb/paymentrequests"
    PAYER_ALIAS = "4671234768"

    def self.configuration(environment: :test, **attributes)
      Swoosh::Configuration.new.tap do |config|
        config.environment = environment
        config.payee_alias = PAYEE_ALIAS
        config.callback_url = CALLBACK_URL
        attributes.each { |name, value| config.public_send(:"#{name}=", value) }
      end
    end

    # A configuration with nothing but the environment set, for asserting on
    # what the gem demands before it will build a payload.
    def self.bare_configuration(environment: :test)
      Swoosh::Configuration.new.tap { |config| config.environment = environment }
    end

    # A directory holding a bundle named the way the gem expects to find it.
    def self.with_cert_dir(environment: :test)
      Dir.mktmpdir do |dir|
        FileUtils.cp(File.join(DIR, MERCHANT), File.join(dir, "swish_#{environment}.p12"))
        yield dir
      end
    end
  end
end
