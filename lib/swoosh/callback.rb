# frozen_string_literal: true

module Swoosh
  # Framework-agnostic handling of the callback Swish POSTs when a payment
  # settles. Include it anywhere and define `swoosh_callback_body` to return the
  # raw request body:
  #
  #   class Handler
  #     include Swoosh::Callback
  #
  #     def initialize(body) = @body = body
  #     def swoosh_callback_body = @body
  #   end
  #
  # Rails controllers get that method for free from Swoosh::Callback::Controller.
  module Callback
    # The body as Swish sent it. UNAUTHENTICATED: Swish does not sign payment
    # callbacks, so anyone who guesses a payment id can post one. Fine for
    # logging; don't settle an order on it.
    def swoosh_callback
      @swoosh_callback ||= Payment.from_callback(swoosh_callback_body)
    end

    # The payment as Swish reports it over mTLS. This is the one to act on: it
    # costs one request on a path that fires once per payment, and it makes the
    # callback and the poller end at exactly the same place.
    def swoosh_verified_payment
      @swoosh_verified_payment ||= Swoosh.find_payment(swoosh_callback.id)
    end

    def swoosh_callback_body
      raise NotImplementedError, "#{self.class} must define #swoosh_callback_body"
    end
  end
end
