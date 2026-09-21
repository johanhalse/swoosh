require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Make code changes take effect immediately without server restart.
  config.enable_reloading = true

  # Do not eager load code on boot.
  config.eager_load = false

  # Show full error reports.
  config.consider_all_requests_local = true

  # Enable server timing.
  config.server_timing = true

  # Enable/disable Action Controller caching. By default Action Controller caching is disabled.
  # Run rails dev:cache to toggle Action Controller caching.
  if Rails.root.join("tmp/caching-dev.txt").exist?
    config.action_controller.perform_caching = true
    config.action_controller.enable_fragment_cache_logging = true
    config.public_file_server.headers = { "cache-control" => "public, max-age=#{2.days.to_i}" }
  else
    config.action_controller.perform_caching = false
  end

  # Change to :null_store to avoid any caching.
  config.cache_store = :memory_store

  # Print deprecation notices to the Rails logger.
  config.active_support.deprecation = :log

  # Highlight code that triggered redirect in logs.
  config.action_dispatch.verbose_redirect_logs = true

  # Suppress logger output for asset requests.
  config.assets.quiet = true

  # Raises error for missing translations.
  # config.i18n.raise_on_missing_translations = true

  # Annotate rendered view with file names.
  config.action_view.annotate_rendered_view_with_filenames = true

  # Raise error when a before_action's only/except options reference missing actions.
  config.action_controller.raise_on_missing_callback_actions = true

  # Swoosh talks to the Swish staging playground (MSS) by default outside
  # production. Flip this to :production when you want to exercise real
  # certificates by hand -- it then expects config/certs/swish_production.p12.
  # config.swoosh.environment = :production
  #
  # config.swoosh.cert_dir      = Rails.root.join("config/certs")
  # config.swoosh.cert_password = ENV["SWISH_CERT_PASSWORD"]
  #
  # Your merchant number, shared by every call. A call may still override it.
  # config.swoosh.payee_alias = "1231181189"
  #
  # Set this only if every payment shares one callback endpoint; otherwise pass
  # callback_url: per call.
  # config.swoosh.callback_url = "https://example.com/swish/callbacks"
end
