# frozen_string_literal: true

require "rails"

module Swoosh
  # Maps `config.swoosh.*` from the host app onto Swoosh::Configuration.
  #
  #   # config/environments/development.rb
  #   config.swoosh.environment = :staging               # default outside production
  #   config.swoosh.cert_dir    = Rails.root.join("config/certs")
  #   config.swoosh.cert_password = ENV["SWISH_CERT_PASSWORD"]
  class Railtie < Rails::Railtie
    config.swoosh = ActiveSupport::OrderedOptions.new

    initializer "swoosh.configure" do |app|
      options = app.config.swoosh

      Swoosh.configure do |swoosh|
        swoosh.environment = options[:environment] || default_environment
        swoosh.cert_dir = options[:cert_dir] || app.root.join("config/certs")
        swoosh.cert_password = options[:cert_password] if options.key?(:cert_password)
        swoosh.root_ca_path = options[:root_ca_path] if options.key?(:root_ca_path)
      end
    end

    # Development and test talk to the Swish staging playground unless the app
    # says otherwise, so only a real production boot reaches for real money.
    def default_environment
      Rails.env.production? ? :production : :test
    end
  end
end
