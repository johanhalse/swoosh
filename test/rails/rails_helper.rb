# frozen_string_literal: true

# Boots the dummy application in test/dummy so the railtie is exercised the way
# a host app would exercise it. Kept out of test/test_helper.rb on purpose: the
# gem's own suite must keep passing with Rails absent.
ENV["RAILS_ENV"] ||= "test"

require_relative "../dummy/config/environment"
require "rails/test_help"
require "fileutils"
require "tmpdir"
require "vcr"
require "webmock/minitest"

require_relative "../support/vcr"
require "swoosh/test"

module Swoosh
  module RailsTestHelper
    GEM_CERTS = File.expand_path("../../certs", __dir__)
    MERCHANT = "Swish_Merchant_TestCertificate_1234679304.p12"

    # Rebuild Swoosh's configuration the way the railtie does, but for an
    # arbitrary Rails.env, so we can assert on development/production booting
    # without actually booting a second application.
    def with_rails_env(env, **options)
      previous = Swoosh.configuration
      Rails.env = env
      Swoosh.reset!
      run_railtie_initializer(options)
      yield Swoosh.configuration
    ensure
      Rails.env = "test"
      Swoosh.instance_variable_set(:@configuration, previous)
      Swoosh.client = nil
    end

    def run_railtie_initializer(options)
      original = Rails.application.config.swoosh
      Rails.application.config.swoosh = original.dup.merge!(options)
      swoosh_initializer.run(Rails.application)
    ensure
      Rails.application.config.swoosh = original
    end

    def swoosh_initializer
      Swoosh::Railtie.instance.initializers.find { |initializer| initializer.name == "swoosh.configure" }
    end

    def drop_in_certificate(dir, environment)
      FileUtils.mkdir_p(dir)
      FileUtils.cp(File.join(GEM_CERTS, MERCHANT), File.join(dir, "swish_#{environment}.p12"))
    end
  end
end

module Minitest
  class Test
    include Swoosh::RailsTestHelper
  end
end
