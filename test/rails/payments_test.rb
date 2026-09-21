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
end
