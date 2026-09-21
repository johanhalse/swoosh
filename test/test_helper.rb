# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "swoosh"

require "minitest/autorun"
require "fileutils"
require "tmpdir"
require "webmock/minitest"

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

    def self.configuration(environment: :test, **attributes)
      Swoosh::Configuration.new.tap do |config|
        config.environment = environment
        attributes.each { |name, value| config.public_send(:"#{name}=", value) }
      end
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
