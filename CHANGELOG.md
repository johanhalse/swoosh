## [Unreleased]

- Drop the `http` gem and reach Swish with `net/http` from the standard library. Swoosh now has no
  runtime dependencies.
- **Verify Swish's server certificate.** The SSL context the gem built set no `verify_mode`, which
  OpenSSL reads as `VERIFY_NONE`, and pushed the bundled DigiCert root into the *client* chain sent
  to Swish rather than into a trust store. The server was therefore never authenticated and the
  merchant certificate would have been handed to anything that answered. `root_ca_path` is now the
  `ca_file` it is documented to be, under `VERIFY_PEER`.
- Replace `Certificates#ssl_context` with `Certificates#configure_ssl(http)`, and `Main#ssl_context`
  with `Main#connection(uri)`: Net::HTTP builds its own context rather than accepting one.
  `ssl_context` also mutated the memoized `ca_certs` array on every call.
- Connection failures now raise `Net::HTTP`'s own errors (`Errno::ECONNREFUSED`, `Net::OpenTimeout`,
  `SocketError`) rather than `HTTP::ConnectionError`. Requests inherit Net::HTTP's 60 second open and
  read timeouts, where http.rb applied none.
- Add `Swoosh.cancel_payment, which withdraws a `CREATED` payment request so an abandoned checkout
  stops occupying the payer's three minutes. Cancelling also drops the stored m-commerce token.
- Raise `Swoosh::PaymentNotCancellable` (RP07, the payer accepted first) and
  `Swoosh::PaymentAlreadyCancelled` (RP08, a second cancel) rather than one `RequestError`: Swish
  reports both as a 422 differing only by a code, and they call for opposite responses.
- Pick the error class from Swish's errorCode as well as the status, via `ResponseError.for`. An
  unrecognised code still raises `RequestError`, so a code Swish adds later stays rescuable.
- Add `TokenStore#delete`, used when a payment can no longer be paid. A store that predates it and
  answers only `read`/`write` is skipped rather than raising.

- `generate_payment` returns a `Swoosh::Payment` carrying the id and the m-commerce token instead of
  the response body, which was empty on success.
- Add `Swoosh.find_payment`, `Payment#app_switch_url`, `Payment#qr_code` and status predicates.
- Raise `Swoosh::RequestError` / `Swoosh::ServerError` on 4xx/5xx, carrying Swish's errorCode,
  with `Swoosh::PaymentNotFound` for 404 so a reconciliation sweep can skip what will never resolve.
- Add `Swoosh::Callback`, a plain module any framework can include, and `Swoosh::Callback::Controller`,
  the Rails concern that supplies only `request.body.read`.
- Add an opt-in token store (`Rails.cache` by default) for the m-commerce token, which Swish issues once.
- Add `swoosh/test` with callback payload builders and WebMock stubs for host applications.

- Build the payment payload from arguments instead of hardcoded Swish test values. `generate_payment`
  now takes `amount` positionally and the rest as keywords, and omits absent fields rather than
  sending null.
- Add `payee_alias`, `callback_url` and `currency` configuration. `payee_alias` is per application
  with a per-call override; `callback_url` is per call, with an optional configured default.

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
