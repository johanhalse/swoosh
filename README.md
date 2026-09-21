# Swoosh

Swish payments for Ruby, with first-class Rails support.

## Installation

```ruby
gem "swoosh"
```

## Certificates

Swish authenticates merchants with a mutual-TLS client certificate issued by your
bank. Swoosh finds it **by name**, in a directory you choose:

```
config/certs/
├── swish_test.p12         # staging (Swish calls this environment MSS)
└── swish_production.p12   # production
```

Drop the bundle your bank issued into that directory under the name matching the
environment it belongs to. Nothing else to configure.

Two conveniences worth knowing:

- **Staging needs no setup at all.** If no `swish_test.p12` is present, Swoosh
  falls back to the Swish test certificates bundled with the gem, so a fresh app
  can talk to the staging playground immediately.
- **Production never falls back.** A missing `swish_production.p12` raises
  `Swoosh::CertificateError` naming the path it looked in, rather than quietly
  running against staging.

The DigiCert root CA that signs the Swish endpoints ships with the gem, so you
don't need to supply one. Override it with `root_ca_path` if that ever changes.

## Rails

The railtie reads `config.swoosh.*`. Every setting is optional:

```ruby
# config/environments/development.rb
Rails.application.configure do
  # Development and test default to :test (staging). Switch to :production when
  # you want to exercise real certificates by hand.
  config.swoosh.environment = :production

  config.swoosh.cert_dir      = Rails.root.join("config/certs")
  config.swoosh.cert_password = ENV["SWISH_CERT_PASSWORD"]
end
```

| Setting | Default |
| --- | --- |
| `environment` | `:production` in `Rails.env.production?`, otherwise `:test` |
| `cert_dir` | `Rails.root.join("config/certs")` |
| `cert_password` | `"swish"` |
| `root_ca_path` | the DigiCert root bundled with the gem |

`environment` accepts `:test`, `:staging` (an alias for `:test`) and
`:production`, as symbols or strings. Anything else raises
`Swoosh::ConfigurationError` at boot.

Then, anywhere in the app:

```ruby
Swoosh.generate_payment(100, "Kaffe")
```

## Without Rails

Nothing in the core depends on Rails, so Sinatra, Hanami and plain Ruby work the
same way:

```ruby
Swoosh.configure do |config|
  config.environment   = :production
  config.cert_dir      = "config/certs"
  config.cert_password = ENV["SWISH_CERT_PASSWORD"]
end

Swoosh.generate_payment(100, "Kaffe")
```

## Development

    $ bin/setup
    $ bundle exec rake

`rake` runs two suites in separate processes: `rake test:gem` exercises the gem
with Rails absent from the process, and `rake test:rails` drives it through the
dummy application in `test/dummy`.

HTTP is recorded with VCR against the Swish staging playground. To re-record,
delete the cassette in `test/cassettes` and run the suite again.

## License

[MIT](https://opensource.org/licenses/MIT).
