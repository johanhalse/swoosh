# frozen_string_literal: true

module Swoosh
  # Framework-agnostic configuration. The Rails railtie maps `config.swoosh.*`
  # onto this; Sinatra/Hanami/plain Ruby can use `Swoosh.configure` directly.
  class Configuration
    # Swish calls the staging environment "MSS". We accept :staging as an alias
    # so `config.swoosh.environment = :staging` reads naturally in an app.
    ENVIRONMENTS = { test: :test, staging: :test, production: :production }.freeze

    DEFAULT_CERT_PASSWORD = "swish"
    DEFAULT_CURRENCY = "SEK"

    # A payment request has to be accepted within three minutes, after which the
    # token is worthless, so there is no reason to keep one longer.
    DEFAULT_TOKEN_TTL = 300

    attr_reader :environment
    attr_accessor :cert_dir, :cert_password, :root_ca_path,
                  :payee_alias, :callback_url, :currency,
                  :token_store, :token_ttl

    def initialize
      @environment = :test
      @cert_dir = nil
      @cert_password = DEFAULT_CERT_PASSWORD
      @root_ca_path = nil

      # The merchant number is the same for a whole codebase, so it belongs in
      # configuration. callback_url has no default on purpose: leave it unset
      # and every call must name one, which is usually what you want.
      @payee_alias = nil
      @callback_url = nil
      @currency = DEFAULT_CURRENCY

      # Opt-in. The railtie points this at Rails.cache; nil just disables the
      # lookup, it never breaks a payment.
      @token_store = nil
      @token_ttl = DEFAULT_TOKEN_TTL
    end

    def environment=(value)
      key = value.to_s.downcase.to_sym
      @environment = ENVIRONMENTS.fetch(key) do
        raise ConfigurationError,
              "Unknown Swoosh environment #{value.inspect}. Valid values: #{ENVIRONMENTS.keys.join(", ")}."
      end
    end

    def production?
      environment == :production
    end
  end
end
