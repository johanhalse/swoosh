# frozen_string_literal: true

require_relative "rails_helper"

class CancelPaymentsTest < ActionDispatch::IntegrationTest
  PAYMENT_ID = "9FEB8DB5130345C79F8DA0C416E7E7DA"

  test "a rails app cancels a payment through the configured client" do
    Swoosh::Test.stub_cancel_payment(PAYMENT_ID)

    delete payment_path(PAYMENT_ID)

    assert_response :success
    assert_equal "CANCELLED", response.parsed_body["status"]
  end

  test "the cancel is a json patch to the v1 endpoint" do
    Swoosh::Test.stub_cancel_payment(PAYMENT_ID)

    delete payment_path(PAYMENT_ID)

    assert_requested(:patch, %r{/api/v1/paymentrequests/#{PAYMENT_ID}\z}) do |request|
      request.headers["Content-Type"] == "application/json-patch+json" &&
        JSON.parse(request.body) == [{ "op" => "replace", "path" => "/status", "value" => "cancelled" }]
    end
  end

  # The app has to be able to tell "too late, they paid" from any other 422, or
  # it will mark a paid order abandoned.
  test "a payment the payer already paid is refused rather than silently cancelled" do
    Swoosh::Test.stub_cancel_payment_refused(PAYMENT_ID, code: "RP07")

    delete payment_path(PAYMENT_ID)

    assert_response :conflict
    assert_equal "RP07", response.parsed_body["error"]
  end

  test "cancelling twice is not an error the app has to show anyone" do
    Swoosh::Test.stub_cancel_payment_refused(PAYMENT_ID, code: "RP08")

    delete payment_path(PAYMENT_ID)

    assert_response :no_content
  end
end

class PaymentsTest < ActionDispatch::IntegrationTest
  test "a rails app creates a swish payment through the configured client" do
    VCR.use_cassette("create_payment") do
      post payments_path, params: { amount: 100, message: "Kaffe" }
    end

    assert_response :created
    assert_equal "test", response.parsed_body["environment"]
  end

  test "the request goes to the swish staging playground" do
    VCR.use_cassette("create_payment") do
      post payments_path, params: { amount: 100, message: "Kaffe" }
    end

    assert_requested :put, %r{\Ahttps://mss\.cpc\.getswish\.net/swish-cpcapi/api/v2/paymentrequests/[0-9A-F]{32}\z}
  end

  test "the payload the app sends carries the amount and message it was given" do
    VCR.use_cassette("create_payment") do
      post payments_path, params: { amount: 250, message: "Bulle" }
    end

    assert_requested(:put, %r{/api/v2/paymentrequests/}) do |request|
      payload = JSON.parse(request.body)

      payload["amount"] == 250 && payload["message"] == "Bulle"
    end
  end

  test "the merchant number comes from config.swoosh without the call site naming it" do
    VCR.use_cassette("create_payment") do
      post payments_path, params: { amount: 100, message: "Kaffe" }
    end

    assert_equal "1231181189", sent_payload["payeeAlias"]
  end

  test "each payment type sends its own callback url" do
    VCR.use_cassette("create_payment") do
      post payments_path, params: { amount: 100, kind: "donation" }
    end

    assert_equal "https://dummy.test/swish/donations", sent_payload["callbackUrl"]
  end

  test "a different payment type sends a different callback url" do
    VCR.use_cassette("create_payment") do
      post payments_path, params: { amount: 100, kind: "order" }
    end

    assert_equal "https://dummy.test/swish/orders", sent_payload["callbackUrl"]
  end

  test "optional fields the app passes reach swish" do
    VCR.use_cassette("create_payment") do
      post payments_path, params: { amount: 100, reference: "order-42" }
    end

    assert_equal "order-42", sent_payload["payeePaymentReference"]
  end

  private

  def sent_payload
    body = nil
    assert_requested(:put, %r{/api/v2/paymentrequests/}) { |request| body = request.body }
    JSON.parse(body)
  end
end
