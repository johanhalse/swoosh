# frozen_string_literal: true

module Swoosh
  # Optional, best-effort storage for the m-commerce token, which Swish hands
  # back exactly once and never again.
  #
  # Backed by anything with ActiveSupport::Cache's read/write signature, so
  # `Rails.cache` drops straight in. A miss is normal and must never raise: the
  # caller creates a fresh payment request instead. Losing a token costs the
  # payer one extra tap, and it expires with the payment window anyway.
  class TokenStore
    PREFIX = "swoosh:token:"

    # A cache that blips must not take a payment down with it. A cache that was
    # wired up wrong should be loud, though, so these come straight back out
    # rather than looking like a miss.
    PROGRAMMING_ERRORS = [NameError, NoMethodError, TypeError, ArgumentError].freeze

    def initialize(backend, ttl:)
      @backend = backend
      @ttl = ttl
    end

    def write(payment_id, token)
      return if @backend.nil? || token.nil?

      @backend.write(key(payment_id), token, expires_in: @ttl)
      token
    rescue *PROGRAMMING_ERRORS
      raise
    rescue StandardError
      token
    end

    def read(payment_id)
      return nil if @backend.nil?

      @backend.read(key(payment_id))
    rescue *PROGRAMMING_ERRORS
      raise
    rescue StandardError
      nil
    end

    def key(payment_id) = "#{PREFIX}#{payment_id}"
  end
end
