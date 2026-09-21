# frozen_string_literal: true

require "rails"
require_relative "callback/controller"

module Swoosh
  # Maps `config.swoosh.*` from the host app onto Swoosh::Configuration.
  #
  #   # config/environments/development.rb
  #   config.swoosh.environment = :staging               # default outside production
  #   config.swoosh.cert_dir    = Rails.root.join("config/certs")
  #   config.swoosh.cert_password = ENV["SWISH_CERT_PASSWORD"]
  #   config.swoosh.payee_alias = "1231181189"           # your merchant number
  class Railtie < Rails::Railtie
    # Passed through only when the app actually set them, so Configuration keeps
    # owning the defaults.
    OPTIONAL_SETTINGS = %i[cert_password root_ca_path payee_alias callback_url currency
                           token_store token_ttl].freeze

    config.swoosh = ActiveSupport::OrderedOptions.new

    initializer "swoosh.configure" do |app|
      options = app.config.swoosh

      Swoosh.configure do |swoosh|
        swoosh.environment = options[:environment] || default_environment
        swoosh.cert_dir = options[:cert_dir] || app.root.join("config/certs")
        swoosh.token_store = options.key?(:token_store) ? options[:token_store] : ::Rails.cache
        OPTIONAL_SETTINGS.each do |setting|
          swoosh.public_send(:"#{setting}=", options[setting]) if options.key?(setting)
        end
      end
    end

    # Development and test talk to the Swish staging playground unless the app
    # says otherwise, so only a real production boot reaches for real money.
    def default_environment
      Rails.env.production? ? :production : :test
    end
  end
end
