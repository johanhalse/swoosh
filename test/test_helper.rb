# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "swoosh"

require "minitest/autorun"
require "vcr"
require "webmock/minitest"

module Swoosh
  module TestCerts
    DIR = File.expand_path("../certs", __dir__)
    MERCHANT = "Swish_Merchant_TestCertificate_1234679304.p12"

    def self.client(env: "test")
      Swoosh::Main.new(env: env, cert_dir: DIR, cert_file: MERCHANT)
    end
  end
end

# Cassettes are recorded against the Swish staging playground (MSS) using the
# test certificates in certs/. To re-record, delete the cassette and run the
# suite again -- the certificates must be unexpired for the handshake to work.
VCR.configure do |config|
  config.cassette_library_dir = File.expand_path("cassettes", __dir__)
  config.hook_into :webmock
  config.default_cassette_options = { record: :once }

  # Every payment request is PUT to a freshly generated instruction id, so the
  # recorded URI never matches on replay. Compare everything but that last segment.
  config.register_request_matcher :swish_uri do |request1, request2|
    File.dirname(URI.parse(request1.uri).path) == File.dirname(URI.parse(request2.uri).path)
  end

  config.default_cassette_options[:match_requests_on] = %i[method swish_uri]
end
