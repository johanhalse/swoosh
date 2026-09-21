# frozen_string_literal: true

require "vcr"

# Cassettes are recorded against the Swish staging playground (MSS) using the
# test certificates in certs/. To re-record, delete the cassette and run the
# suite again -- the certificates must be unexpired for the handshake to work.
VCR.configure do |config|
  config.cassette_library_dir = File.expand_path("../cassettes", __dir__)
  config.hook_into :webmock
  config.default_cassette_options = { record: :once }

  # Every payment request is PUT to a freshly generated instruction id, so the
  # recorded URI never matches on replay. Compare everything but that last segment.
  config.register_request_matcher :swish_uri do |request1, request2|
    File.dirname(URI.parse(request1.uri).path) == File.dirname(URI.parse(request2.uri).path)
  end

  config.default_cassette_options[:match_requests_on] = %i[method swish_uri]
end
