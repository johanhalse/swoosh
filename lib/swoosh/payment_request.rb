# frozen_string_literal: true

module Swoosh
  # Builds the body of a Swish payment request.
  #
  # payee_alias (your merchant number) and callback_url fall back to the
  # configuration when a call doesn't name them; everything else is per-call,
  # because it describes this payment rather than this application.
  class PaymentRequest
    # Swish rejects a payload carrying keys it doesn't expect, so anything left
    # nil is dropped rather than sent as null.
    def initialize(configuration:, amount:, **options)
      @configuration = configuration
      @amount = amount
      @options = options
    end

    def to_h
      {
        payeeAlias: payee_alias,
        callbackUrl: callback_url,
        amount: @amount,
        currency: currency,
        message: @options[:message],
        payerAlias: @options[:payer_alias],
        payeePaymentReference: @options[:payee_payment_reference],
        payerSSN: @options[:payer_ssn],
        ageLimit: @options[:age_limit]
      }.compact
    end

    def payee_alias
      @options[:payee_alias] || @configuration.payee_alias ||
        raise(ConfigurationError, missing_message("payee_alias", "your Swish merchant number"))
    end

    def callback_url
      @options[:callback_url] || @configuration.callback_url ||
        raise(ConfigurationError, missing_message("callback_url", "the HTTPS URL Swish posts the result to"))
    end

    def currency
      @options[:currency] || @configuration.currency
    end

    private

    def missing_message(name, description)
      "Swoosh needs a #{name} (#{description}). Pass #{name}: to the call, " \
        "or set config.swoosh.#{name} once for the whole application."
    end
  end
end
