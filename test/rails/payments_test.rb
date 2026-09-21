# frozen_string_literal: true

require_relative "rails_helper"

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
