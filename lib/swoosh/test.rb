# frozen_string_literal: true

# Not loaded with the gem -- require "swoosh/test" from your test helper.
require "json"
require_relative "../swoosh"

module Swoosh
  # Builders and stubs for exercising Swish flows without touching the network.
  module Test
    CALLBACK_DEFAULTS = {
      "payeePaymentReference" => "ABC123",
      "paymentReference" => "A58D39A2632D488EA8F00AA88251336B",
      "callbackUrl" => "https://example.com/swish/callbacks",
      "payerAlias" => "4671234768",
      "payeeAlias" => "1231181189",
      "amount" => 100.0,
      "currency" => "SEK",
      "message" => "",
      "status" => "PAID",
      "dateCreated" => "2026-09-21T08:26:45.746Z",
      "datePaid" => "2026-09-21T08:27:01.000Z",
      "errorCode" => nil,
      "errorMessage" => nil
    }.freeze

    # Swish's refusals, verbatim from the staging playground. RP07 is the payer
    # winning the race (the payment is PAID); RP08 is a second cancel.
    CANCEL_REFUSALS = {
      "RP07" => "The payment request can not be cancelled.",
      "RP08" => "The payment request has been cancelled."
    }.freeze

    module_function

    # The body Swish POSTs to your callback URL, shaped like the real thing.
    def callback_payload(id:, status: "PAID", **overrides)
      CALLBACK_DEFAULTS
        .merge("id" => id, "status" => status)
        .merge(error_defaults(status))
        .merge(overrides.transform_keys(&:to_s))
    end

    def callback_json(...) = JSON.generate(callback_payload(...))

    def payment(id: SecureRandom.uuid.delete("-").upcase, status: "CREATED", token: nil, **overrides)
      Payment.new(callback_payload(id: id, status: status, **overrides), token: token)
    end

    # Requires webmock. Stubs the mTLS GET that find_payment and
    # swoosh_verified_payment make.
    def stub_find_payment(id, status: "PAID", **overrides)
      require "webmock"
      WebMock::API.stub_request(:get, %r{/api/v1/paymentrequests/#{id}\z})
                  .to_return(
                    status: 200,
                    body: callback_json(id: id, status: status, **overrides),
                    headers: { "Content-Type" => "application/json" }
                  )
    end

    # Stubs creating a payment, including the token header when one is wanted.
    def stub_generate_payment(token: "37ca502428ff40c1b17310787165236f")
      require "webmock"
      headers = { "Content-Length" => "0" }
      headers["PaymentRequestToken"] = token if token
      WebMock::API.stub_request(:put, %r{/api/v2/paymentrequests/})
                  .to_return(status: 201, body: "", headers: headers)
    end

    # Stubs the PATCH that cancel_payment makes. Swish answers with the payment
    # in its new state, so this returns a CANCELLED one by default.
    def stub_cancel_payment(id, status: "CANCELLED", **overrides)
      require "webmock"
      WebMock::API.stub_request(:patch, %r{/api/v1/paymentrequests/#{id}\z})
                  .to_return(
                    status: 200,
                    body: callback_json(id: id, status: status, **overrides),
                    headers: { "Content-Type" => "application/json" }
                  )
    end

    # Stubs a cancel Swish refuses. Defaults to RP07, the race worth testing:
    # the payer accepted before your PATCH landed.
    def stub_cancel_payment_refused(id, code: "RP07")
      require "webmock"
      WebMock::API.stub_request(:patch, %r{/api/v1/paymentrequests/#{id}\z})
                  .to_return(
                    status: 422,
                    body: JSON.generate(
                      [{ "errorCode" => code, "errorMessage" => CANCEL_REFUSALS.fetch(code),
                         "additionalInformation" => nil }]
                    ),
                    headers: { "Content-Type" => "application/json" }
                  )
    end

    def stub_qr_code(body: "\x89PNG\r\n\x1a\n")
      require "webmock"
      WebMock::API.stub_request(:post, Swoosh::QrCode::ENDPOINT)
                  .to_return(status: 200, body: body, headers: { "Content-Type" => "image/png" })
    end

    # Swish fills errorCode on more than just ERROR: a successfully cancelled
    # payment carries RP08 while its status is CANCELLED, not ERROR.
    def error_defaults(status)
      case status
      when "ERROR"
        { "errorCode" => "TM01", "errorMessage" => "Swish timed out before the payment was started" }
      when "CANCELLED"
        { "errorCode" => "RP08", "errorMessage" => CANCEL_REFUSALS.fetch("RP08") }
      else
        {}
      end
    end
  end
end
