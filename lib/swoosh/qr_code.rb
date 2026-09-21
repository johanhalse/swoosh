# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Swoosh
  # Swish generates payment QR codes from a separate, public host -- no client
  # certificate involved, which is why this doesn't go through the mTLS client.
  module QrCode
    ENDPOINT = "https://mpc.getswish.net/qrg-swish/api/v1/commerce"
    FORMATS = %w[png jpg svg].freeze
    # Swish rejects anything smaller with a 400, for every format.
    MIN_SIZE = 300
    DEFAULT_SIZE = 300

    module_function

    # Returns the image bytes. Render with `send_data qr, type: "image/png"`.
    def generate(token, size: DEFAULT_SIZE, format: "png", border: 0, transparent: false)
      raise ArgumentError, "Unknown QR format #{format.inspect}. Use #{FORMATS.join(", ")}." unless
        FORMATS.include?(format.to_s)
      raise ArgumentError, "Swish requires a QR size of at least #{MIN_SIZE} (got #{size})." if size < MIN_SIZE

      response = Net::HTTP.post(
        URI.parse(ENDPOINT),
        JSON.generate({ token: token, size: size, format: format.to_s, border: border, transparent: transparent }),
        "Content-Type" => "application/json"
      )
      raise ResponseError.new(status: response.code.to_i, body: response.body.to_s) unless
        response.is_a?(Net::HTTPSuccess)

      response.body
    end
  end
end
