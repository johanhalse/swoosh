## [Unreleased]

- Require Ruby >= 3.2; develop and test against Ruby 4.0.7.
- Bump `http` to ~> 6.0, and the development dependencies (rake, rubocop, rubocop-minitest, minitest).
- Replace `pry` with `debug`.
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
