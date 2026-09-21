# frozen_string_literal: true

require "cgi"
require "json"

module Swoosh
  # A Swish payment request, however you came by it: the response to creating
  # one, a poll, or a callback body.
  #
  # Only #id and #token can't be re-derived -- everything else comes back from
  # Swoosh.find_payment.
  class Payment
    # Swish stops changing a payment once it reaches one of these.
    TERMINAL_STATUSES = %w[PAID DECLINED ERROR CANCELLED].freeze
    CREATED = "CREATED"

    ATTRIBUTES = {
      id: "id",
      status: "status",
      amount: "amount",
      currency: "currency",
      message: "message",
      callback_url: "callbackUrl",
      payee_alias: "payeeAlias",
      payer_alias: "payerAlias",
      payee_payment_reference: "payeePaymentReference",
      payment_reference: "paymentReference",
      date_created: "dateCreated",
      date_paid: "datePaid",
      error_code: "errorCode",
      error_message: "errorMessage"
    }.freeze

    attr_reader :token, :attributes

    # Swish only ever hands the m-commerce token back in the 201 response
    # header, so it has to be carried alongside rather than read from the body.
    def initialize(attributes = {}, token: nil)
      @attributes = attributes.transform_keys(&:to_s)
      @token = token
    end

    def self.from_json(json, token: nil)
      new(json.nil? || json.empty? ? {} : JSON.parse(json), token: token)
    end

    # The body Swish POSTs to your callback URL is a Payment Request object.
    def self.from_callback(json)
      from_json(json)
    end

    ATTRIBUTES.each do |name, key|
      define_method(name) { @attributes[key] }
    end

    def paid? = status == "PAID"
    def declined? = status == "DECLINED"
    def cancelled? = status == "CANCELLED"
    def error? = status == "ERROR"

    def terminal? = TERMINAL_STATUSES.include?(status)
    def pending? = !terminal?

    # Present for m-commerce (no payer_alias), absent for e-commerce.
    def token? = !token.nil?

    # Opens the Swish app with this payment preloaded. Same-device flow.
    # return_url is where Swish (or BankID) sends the payer afterwards; it is a
    # UX return only, and never evidence that the payment succeeded.
    def app_switch_url(return_url:)
      require_token!(:app_switch_url)

      "swish://paymentrequest?token=#{token}&callbackurl=#{CGI.escape(return_url.to_s)}"
    end

    # Image bytes for the other-device flow. Served from Swish's public QR host.
    def qr_code(**options)
      require_token!(:qr_code)

      QrCode.generate(token, **options)
    end

    def to_h = @attributes.dup

    def ==(other)
      other.is_a?(Payment) && other.attributes == attributes && other.token == token
    end
    alias eql? ==

    def hash = [attributes, token].hash

    private

    def require_token!(method)
      return if token?

      raise Error, "##{method} needs an m-commerce token. Omit payer_alias when creating the " \
                   "payment so Swish issues one, or use Swoosh.token_for(id) to recover it."
    end
  end
end
