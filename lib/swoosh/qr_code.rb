# frozen_string_literal: true

require "http"

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

      response = HTTP.post(
        ENDPOINT,
        json: { token: token, size: size, format: format.to_s, border: border, transparent: transparent }
      )
      raise ResponseError.new(status: response.status.code, body: response.to_s) unless response.status.success?

      response.to_s
    end
  end
end
