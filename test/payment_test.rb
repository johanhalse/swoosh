# frozen_string_literal: true

require "test_helper"
require "json"

class PaymentTest < Minitest::Test
  def test_it_reads_the_swish_payload_with_ruby_names
    payment = Swoosh::Payment.new(Swoosh::Test.callback_payload(id: "ABC", status: "PAID"))

    assert_equal "ABC", payment.id
    assert_equal "ABC123", payment.payee_payment_reference
    assert_equal "A58D39A2632D488EA8F00AA88251336B", payment.payment_reference
    assert_equal "1231181189", payment.payee_alias
  end

  def test_paid_is_terminal
    payment = Swoosh::Payment.new({ "status" => "PAID" })

    assert_predicate payment, :paid?
    assert_predicate payment, :terminal?
    refute_predicate payment, :pending?
  end

  def test_created_is_pending
    payment = Swoosh::Payment.new({ "status" => Swoosh::Payment::CREATED })

    assert_predicate payment, :pending?
    refute_predicate payment, :terminal?
  end

  def test_every_settled_status_counts_as_terminal
    %w[PAID DECLINED ERROR CANCELLED].each do |status|
      assert_predicate Swoosh::Payment.new({ "status" => status }), :terminal?, "#{status} should be terminal"
    end
  end

  def test_the_settled_statuses_each_have_a_predicate
    assert_predicate Swoosh::Payment.new({ "status" => "DECLINED" }), :declined?
    assert_predicate Swoosh::Payment.new({ "status" => "CANCELLED" }), :cancelled?
    assert_predicate Swoosh::Payment.new({ "status" => "ERROR" }), :error?
  end

  def test_a_timed_out_payment_carries_the_swish_error_code
    payment = Swoosh::Payment.new(Swoosh::Test.callback_payload(id: "ABC", status: "ERROR"))

    assert_predicate payment, :error?
    assert_equal "TM01", payment.error_code
  end

  def test_it_parses_a_callback_body
    json = Swoosh::Test.callback_json(id: "ABC", status: "PAID")
    payment = Swoosh::Payment.from_callback(json)

    assert_equal "ABC", payment.id
    assert_predicate payment, :paid?
  end

  def test_an_empty_body_does_not_blow_up
    payment = Swoosh::Payment.from_json("")

    assert_nil payment.id
    assert_nil payment.status
  end

  def test_two_payments_with_the_same_data_are_equal
    assert_equal Swoosh::Payment.new({ "id" => "A" }, token: "t"), Swoosh::Payment.new({ "id" => "A" }, token: "t")
    refute_equal Swoosh::Payment.new({ "id" => "A" }, token: "t"), Swoosh::Payment.new({ "id" => "A" })
  end
end

class TokenStoreTest < Minitest::Test
  include Swoosh::Fakes

  def test_it_round_trips_a_token
    store = Swoosh::TokenStore.new(MemoryBackend.new, ttl: 300)
    store.write("ABC", "tok")

    assert_equal "tok", store.read("ABC")
  end

  def test_it_writes_with_the_configured_expiry
    backend = MemoryBackend.new
    Swoosh::TokenStore.new(backend, ttl: 120).write("ABC", "tok")

    assert_equal({ expires_in: 120 }, backend.writes.first.last)
  end

  def test_it_namespaces_its_keys
    assert_equal "swoosh:token:ABC", Swoosh::TokenStore.new(nil, ttl: 300).key("ABC")
  end

  def test_no_backend_reads_nil_rather_than_raising
    store = Swoosh::TokenStore.new(nil, ttl: 300)
    store.write("ABC", "tok")

    assert_nil store.read("ABC")
  end

  def test_a_miss_is_nil_so_the_caller_can_start_a_new_request
    assert_nil Swoosh::TokenStore.new(MemoryBackend.new, ttl: 300).read("never-written")
  end

  def test_a_broken_cache_never_takes_a_payment_down
    store = Swoosh::TokenStore.new(BrokenBackend.new, ttl: 300)

    assert_equal "tok", store.write("ABC", "tok")
    assert_nil store.read("ABC")
  end

  # Swallowing these would turn "you wired the store up wrong" into a silent
  # cache miss that only shows up as a payer having to tap twice.
  def test_a_miswired_store_is_loud_rather_than_silent
    store = Swoosh::TokenStore.new(MiswiredBackend.new, ttl: 300)

    assert_raises(NoMethodError) { store.write("ABC", "tok") }
    assert_raises(NameError) { store.read("ABC") }
  end

  def test_deleting_drops_the_token
    store = Swoosh::TokenStore.new(MemoryBackend.new, ttl: 300)
    store.write("ABC", "tok")
    store.delete("ABC")

    assert_nil store.read("ABC")
  end

  def test_deleting_something_that_was_never_written_is_not_an_error
    assert_nil Swoosh::TokenStore.new(MemoryBackend.new, ttl: 300).delete("never-written")
  end

  def test_no_backend_deletes_nothing_rather_than_raising
    assert_nil Swoosh::TokenStore.new(nil, ttl: 300).delete("ABC")
  end

  def test_a_broken_cache_does_not_fail_a_delete
    assert_nil Swoosh::TokenStore.new(BrokenBackend.new, ttl: 300).delete("ABC")
  end

  # delete arrived after read and write, so unlike those two a store that lacks
  # it is an older contract rather than a miswiring, and must stay quiet: the
  # TTL clears the token anyway.
  def test_a_store_without_delete_is_skipped_rather_than_blowing_up
    assert_nil Swoosh::TokenStore.new(UndeletableBackend.new, ttl: 300).delete("ABC")
  end
end

class QrCodeTest < Minitest::Test
  TOKEN = "37ca502428ff40c1b17310787165236f"

  def test_it_returns_the_image_bytes
    Swoosh::Test.stub_qr_code(body: "PNGDATA")

    assert_equal "PNGDATA", Swoosh::QrCode.generate(TOKEN)
  end

  def test_it_posts_the_token_and_options_to_the_public_qr_host
    Swoosh::Test.stub_qr_code
    Swoosh::QrCode.generate(TOKEN, size: 600, format: "svg")

    assert_requested(:post, Swoosh::QrCode::ENDPOINT) do |request|
      payload = JSON.parse(request.body)

      payload["token"] == TOKEN && payload["size"] == 600 && payload["format"] == "svg"
    end
  end

  # Swish 400s below 300, so catch it before the round trip.
  def test_it_rejects_a_size_swish_would_refuse
    error = assert_raises(ArgumentError) { Swoosh::QrCode.generate(TOKEN, size: 200) }

    assert_match "at least 300", error.message
  end

  def test_it_rejects_an_unknown_format
    error = assert_raises(ArgumentError) { Swoosh::QrCode.generate(TOKEN, format: "bmp") }

    assert_match "png, jpg, svg", error.message
  end

  def test_it_raises_when_the_qr_host_refuses
    Swoosh::Test.stub_qr_code
    WebMock.stub_request(:post, Swoosh::QrCode::ENDPOINT).to_return(status: 400, body: "nope")

    assert_raises(Swoosh::ResponseError) { Swoosh::QrCode.generate(TOKEN) }
  end
end
