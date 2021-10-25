# frozen_string_literal: true

require "rails"

module Swoosh
  class Railtie < Rails::Railtie
    config.swoosh = ActiveSupport::OrderedOptions.new

    initializer "swoosh.configure" do |app|
      Swoosh.client = Main.new(
        env: app.config.swoosh[:environment] || "test"
      )
    end
  end
end
