## [Unreleased]

- Find certificates by name: `swish_test.p12` / `swish_production.p12` in a configurable `cert_dir`.
  Staging falls back to the certificates bundled with the gem; production raises rather than falling back.
- Add `Swoosh::Configuration` and `Swoosh.configure`, so the core no longer depends on Rails.
- Rework the railtie around `config.swoosh.{environment,cert_dir,cert_password,root_ca_path}`, defaulting
  to staging outside `Rails.env.production?`.
- Add a dummy Rails application in `test/dummy` and a second suite that drives the gem through it.
  `rake` now runs `test:gem` (Rails absent) and `test:rails` in separate processes.

- Require Ruby >= 3.2; develop and test against Ruby 4.0.7.
- Bump `http` to ~> 6.0, and the development dependencies (rake, rubocop, rubocop-minitest, minitest).
- Replace `pry` with `debug`.
- Add `vcr` + `webmock`, and record the payment-request flow against the Swish staging playground (MSS)
  into `test/cassettes/`, so the suite exercises a real 201 response offline.
- Load `rubocop-minitest` and `rubocop-rake` as RuboCop plugins (they were installed but never enabled).
- Refresh the bundled Swish test certificates. The previous merchant certificates expired in 2022 and
  were encrypted with `pbeWithSHA1And40BitRC2-CBC`, which OpenSSL 3 refuses to parse without the legacy
  provider. The current bundle is valid until 2027-09-11 and uses PBES2/PBKDF2/AES-256-CBC.
- Replace the `Swish_TLS_RootCA.pem` root CA with DigiCert Global Root G2. Both `mss.cpc.getswish.net`
  and `cpc.getswish.net` now chain to G2; the previous DigiCert Global Root CA no longer verifies them.
- Add the Swish technical supplier test certificate (`Swish_TechnicalSupplier_TestCertificate_9870474641`).
- Fix `Main#generate_payment` to accept the `message` argument it passes on to `#data`.
- Make the certificate directory, filename and password injectable via `Main.new`.
- Drop the dead `Main#client` method (it referenced an undefined `Client` and `@private_key`).

## [0.1.0] - 2021-10-22

- Initial release
