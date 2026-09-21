# frozen_string_literal: true

require_relative "rails_helper"

class CallbacksTest < ActionDispatch::IntegrationTest
  PAYMENT_ID = "3564B0C2CA0F4EFC860EEC409092EB8C"

  setup { Rails.configuration.x.settled_payments = [] }

  test "the concern hands the controller the parsed callback body" do
    Swoosh::Test.stub_find_payment(PAYMENT_ID, status: "PAID")
    post_callback(status: "PAID")

    assert_response :success
    assert_equal PAYMENT_ID, response.parsed_body["id"]
  end

  test "it verifies the payment against swish rather than trusting the post" do
    Swoosh::Test.stub_find_payment(PAYMENT_ID, status: "PAID")
    post_callback(status: "PAID")

    assert_requested :get, %r{/api/v1/paymentrequests/#{PAYMENT_ID}}
  end

  test "a paid payment settles the order" do
    Swoosh::Test.stub_find_payment(PAYMENT_ID, status: "PAID")
    post_callback(status: "PAID")

    assert_equal [PAYMENT_ID], Rails.configuration.x.settled_payments
  end

  # Callbacks are unauthenticated, so this is the attack that matters.
  test "a forged PAID callback settles nothing when swish says otherwise" do
    Swoosh::Test.stub_find_payment(PAYMENT_ID, status: "DECLINED")
    post_callback(status: "PAID")

    assert_equal "PAID", response.parsed_body["claimed"]
    assert_equal "DECLINED", response.parsed_body["status"]
    assert_empty Rails.configuration.x.settled_payments
  end

  test "a timed out payment reports the swish error code" do
    Swoosh::Test.stub_find_payment(PAYMENT_ID, status: "ERROR")
    post_callback(status: "ERROR")

    assert_equal "ERROR", response.parsed_body["status"]
    assert_empty Rails.configuration.x.settled_payments
  end

  private

  def post_callback(status:)
    post swish_callbacks_path,
         params: Swoosh::Test.callback_json(id: PAYMENT_ID, status: status),
         headers: { "CONTENT_TYPE" => "application/json" }
  end
end

class RailsTokenStoreTest < ActiveSupport::TestCase
  test "the railtie points the token store at Rails.cache by default" do
    with_rails_env("development") do |config|
      assert_equal Rails.cache, config.token_store
    end
  end

  test "an app can disable the token store" do
    with_rails_env("development", token_store: nil) do |config|
      assert_nil config.token_store
    end
  end

  test "an app can set its own ttl" do
    with_rails_env("development", token_ttl: 60) do |config|
      assert_equal 60, config.token_ttl
    end
  end

  test "a token written on create can be read back by payment id" do
    store = ActiveSupport::Cache::MemoryStore.new

    with_rails_env("development", token_store: store) do
      Swoosh::Test.stub_generate_payment(token: "abc123")
      payment = Swoosh.generate_payment(100, callback_url: "https://example.com/cb")

      assert_equal "abc123", Swoosh.token_for(payment.id)
    end
  end

  test "a miss returns nil so the caller can start a fresh request" do
    with_rails_env("development", token_store: ActiveSupport::Cache::MemoryStore.new) do
      assert_nil Swoosh.token_for("NEVER-CREATED")
    end
  end

  # Rails.cache is NullStore in the test environment, which must not break anything.
  test "a null store degrades to no fast path rather than failing" do
    with_rails_env("test", token_store: ActiveSupport::Cache::NullStore.new) do
      Swoosh::Test.stub_generate_payment(token: "abc123")
      payment = Swoosh.generate_payment(100, callback_url: "https://example.com/cb")

      assert_equal "abc123", payment.token
      assert_nil Swoosh.token_for(payment.id)
    end
  end
end
