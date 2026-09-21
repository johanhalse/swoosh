# frozen_string_literal: true

module Swoosh
  # Framework-agnostic configuration. The Rails railtie maps `config.swoosh.*`
  # onto this; Sinatra/Hanami/plain Ruby can use `Swoosh.configure` directly.
  class Configuration
    # Swish calls the staging environment "MSS". We accept :staging as an alias
    # so `config.swoosh.environment = :staging` reads naturally in an app.
    ENVIRONMENTS = { test: :test, staging: :test, production: :production }.freeze

    DEFAULT_CERT_PASSWORD = "swish"

    attr_reader :environment
    attr_accessor :cert_dir, :cert_password, :root_ca_path

    def initialize
      @environment = :test
      @cert_dir = nil
      @cert_password = DEFAULT_CERT_PASSWORD
      @root_ca_path = nil
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
