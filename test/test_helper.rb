# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "swoosh"

require "minitest/autorun"

module Swoosh
  module TestCerts
    DIR = File.expand_path("../certs", __dir__)
    MERCHANT = "Swish_Merchant_TestCertificate_1234679304.p12"

    def self.client(env: "test")
      Swoosh::Main.new(env: env, cert_dir: DIR, cert_file: MERCHANT)
    end
  end
end
