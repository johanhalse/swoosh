# frozen_string_literal: true

require "test_helper"

# What a Sinatra/Hanami/plain-Ruby handler looks like: include the module and
# say where the body comes from.
class PlainHandler
  include Swoosh::Callback

  def initialize(body)
    @body = body
  end

  def swoosh_callback_body = @body
end

class CallbackTest < Minitest::Test
  PAYMENT_ID = "3564B0C2CA0F4EFC860EEC409092EB8C"

  def setup
    Swoosh.client = Swoosh::TestCerts.client
  end

  # webmock/minitest hooks teardown to reset stubs and request counts, so this
  # must call super or counters leak into the next test.
  def teardown
    super
    Swoosh.client = nil
  end

  def test_it_parses_the_body_swish_posts
    payment = PlainHandler.new(Swoosh::Test.callback_json(id: PAYMENT_ID, status: "PAID")).swoosh_callback

    assert_equal PAYMENT_ID, payment.id
    assert_predicate payment, :paid?
  end

  def test_it_works_without_rails_loaded
    refute defined?(Rails), "the gem suite must stay Rails-free"
    assert_kind_of Swoosh::Payment, PlainHandler.new(Swoosh::Test.callback_json(id: PAYMENT_ID)).swoosh_callback
  end

  def test_verifying_re_fetches_the_payment_from_swish
    Swoosh::Test.stub_find_payment(PAYMENT_ID, status: "PAID")
    payment = PlainHandler.new(Swoosh::Test.callback_json(id: PAYMENT_ID, status: "PAID")).swoosh_verified_payment

    assert_predicate payment, :paid?
    assert_requested :get, %r{/api/v1/paymentrequests/#{PAYMENT_ID}}
  end

  # The callback is unauthenticated, so a forged body claiming PAID must not
  # survive verification.
  def test_a_forged_callback_does_not_survive_verification
    Swoosh::Test.stub_find_payment(PAYMENT_ID, status: "DECLINED")
    handler = PlainHandler.new(Swoosh::Test.callback_json(id: PAYMENT_ID, status: "PAID"))

    assert_predicate handler.swoosh_callback, :paid?
    refute_predicate handler.swoosh_verified_payment, :paid?
    assert_predicate handler.swoosh_verified_payment, :declined?
  end

  def test_it_only_verifies_once_per_request
    Swoosh::Test.stub_find_payment(PAYMENT_ID)
    handler = PlainHandler.new(Swoosh::Test.callback_json(id: PAYMENT_ID))
    3.times { handler.swoosh_verified_payment }

    assert_requested :get, %r{/api/v1/paymentrequests/#{PAYMENT_ID}}, times: 1
  end

  def test_an_includer_that_forgets_the_body_gets_told_so
    klass = Class.new { include Swoosh::Callback }
    error = assert_raises(NotImplementedError) { klass.new.swoosh_callback }

    assert_match "swoosh_callback_body", error.message
  end
end
