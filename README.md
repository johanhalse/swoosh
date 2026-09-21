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
| `payee_alias` | none -- your Swish merchant number |
| `callback_url` | none -- see below |
| `currency` | `"SEK"` |
| `token_store` | `Rails.cache`; `nil` disables |
| `token_ttl` | 300 seconds |

`environment` accepts `:test`, `:staging` (an alias for `:test`) and
`:production`, as symbols or strings. Anything else raises
`Swoosh::ConfigurationError` at boot.

## Creating a payment

```ruby
payment = Swoosh.generate_payment(
  199,
  callback_url:            swish_callbacks_url,
  payee_payment_reference: order.ocr,      # your matching key, e.g. "ABC123"
  message:                 "Order #{order.number}"
)

order.update!(swish_payment_id: payment.id)   # persist before you render anything
```

`amount` is the only positional argument. Everything else is a keyword:

| Keyword | |
| --- | --- |
| `callback_url` | HTTPS URL Swish posts the result to. Required. |
| `payee_alias` | overrides the configured merchant number |
| `message` | shown to the payer |
| `payer_alias` | the payer's number. **Omit it** for the Swish-app flow, which is what issues a token |
| `payee_payment_reference` | your own reference: `a-z A-Z 0-9 -_.+*/`, 1-36 characters |
| `payer_ssn`, `age_limit` | passed through to Swish when given |
| `currency` | defaults to `SEK` |

Anything left out is omitted from the request rather than sent as null, which
matters for `payer_alias`: sending it null breaks the Swish-app flow.

A 4xx or 5xx raises `Swoosh::RequestError` / `Swoosh::ServerError`, carrying
Swish's own code:

```ruby
rescue Swoosh::RequestError => e
  e.status        # => 422
  e.error_code    # => "BE18"
  e.error_message # => "Payer alias is invalid"
end
```

### payee_alias vs callback_url

Your merchant number is the same everywhere, so configure it once. A call can
still override it if you bill through more than one merchant.

The callback is different: one application usually has several kinds of payment
that want different endpoints, so **`callback_url` is per call**. Configure
`callback_url` only if every payment in the app shares one endpoint -- leave it
unset and Swoosh requires each call to name one.

## Presenting the payment

Both flows use the same token, so you decide at render time, not request time:

```ruby
# same device -- hand the payer to the Swish app
redirect_to payment.app_switch_url(return_url: order_url(order))

# other device -- show a QR code
send_data payment.qr_code(size: 300), type: "image/png"
```

`qr_code` accepts `size:` (minimum 300, which Swish enforces), `format:` (`png`,
`jpg`, `svg`), `border:` and `transparent:`. It is served from Swish's public QR
host, so it needs no certificate.

Supply `payer_alias` instead and Swish notifies that number directly; no token is
issued and both methods above raise.

The `return_url` is a **UX return only**. It tells you nothing about whether the
payment succeeded, and in-app browsers drop it routinely.

## Receiving the callback

Swish POSTs the payment to your `callback_url` when it settles. **Swish does not
sign these**, so anyone who guesses a payment id can post one. Verify before you
act:

```ruby
class Swish::CallbacksController < ApplicationController
  include Swoosh::Callback::Controller
  skip_forgery_protection

  def create
    payment = swoosh_verified_payment              # re-fetched from Swish over mTLS
    Order.find_by!(swish_payment_id: payment.id).settle! if payment.paid?
    head :ok
  end
end
```

| | |
| --- | --- |
| `swoosh_callback` | the POSTed body, parsed. Unauthenticated -- fine for logging |
| `swoosh_verified_payment` | asks Swish directly. Act on this one |

Outside Rails, include the plain module and say where the body comes from:

```ruby
class CallbackHandler
  include Swoosh::Callback

  def initialize(body) = @body = body
  def swoosh_callback_body = @body
end
```

`Swoosh::Callback::Controller` is only that module plus `request.body.read`.

## Cancelling

A payment request the payer never answers occupies the full three minutes.
Cancel it and the payer's Swish app stops offering it immediately:

```ruby
Swoosh.cancel_payment(order.swish_payment_id)   # => Payment, status CANCELLED
```

Only a `CREATED` payment can be cancelled, which makes this an inherently racy
call: on a page people abandon by paying, the payer often accepts somewhere
between your decision to cancel and the request landing. Swish reports both
outcomes as a 422 differing only by a code in the body, so Swoosh gives them
separate classes:

```ruby
begin
  Swoosh.cancel_payment(order.swish_payment_id)
rescue Swoosh::PaymentAlreadyCancelled
  # RP08. Already where you wanted it -- usually nothing to do.
rescue Swoosh::PaymentNotCancellable
  # RP07. The payer got there first. This order may be PAID.
  order.settle!(Swoosh.find_payment(order.swish_payment_id))
end
```

**A failed cancel is never licence to treat an order as abandoned.** `RP07`
means the payment left `CREATED`, and the overwhelmingly likely reason is that
it was paid. Poll before you decide anything.

One wrinkle worth knowing, because it looks like a bug: a *successful* cancel
comes back carrying `errorCode` `"RP08"` while its status is `CANCELLED`. Swish
populates that field on more than failures, so read `status` -- or
`payment.cancelled?` -- rather than treating a present `error_code` as trouble.

```ruby
payment = Swoosh.cancel_payment(id)
payment.cancelled?   # => true
payment.error?       # => false  -- ERROR is a different status
payment.error_code   # => "RP08"
```

Cancelling also drops any stored m-commerce token, so `Swoosh.token_for` won't
hand back something that still renders a QR nobody can pay.

## Polling

```ruby
payment = Swoosh.find_payment(order.swish_payment_id)
payment.paid?      # also declined? cancelled? error?
payment.pending?   # still CREATED
payment.error_code # e.g. "TM01" when the payer ran out of time
```

**Swish delivers each callback exactly once and never retries.** A deploy or a
brief 502 loses it permanently, so polling is not optional:

- Your waiting page should poll **your** app, reading your own database. Never
  block a request on Swish.
- A background job sweeps anything still `CREATED` after ~3 minutes and calls
  `find_payment`. That closes the gap.

Since the callback controller also ends at a verified `Payment`, both paths run
the same settling code -- make it idempotent once.

Statuses are `CREATED`, `PAID`, `DECLINED`, `ERROR`, `CANCELLED`. A payer has
three minutes to accept; after that Swish reports `ERROR` with code `TM01`.

### Reconciliation

Swoosh deliberately ships no sweep: it would need your database and your
scheduler. It gives you `find_payment` and error classes precise enough to build
one in a dozen lines.

```ruby
class ReconcileSwishPayments
  def call
    Order.awaiting_swish.where(created_at: ..3.minutes.ago).find_each do |order|
      settle(order)
    rescue Swoosh::PaymentNotFound
      order.record_swish_lookup_miss!   # do NOT treat as "never happened"
    rescue Swoosh::ServerError
      next                              # transient; next sweep picks it up
    end
  end

  private

  def settle(order)
    payment = Swoosh.find_payment(order.swish_payment_id)
    order.settle!(payment) if payment.terminal?
  end
end
```

Rescue per row, not per batch: one bad row shouldn't abort the sweep.

**A 404 is not proof the payment doesn't exist.** The integration guide defines
it as "the Payment request was not found, *or it was not created by the
merchant*" -- so polling a real, possibly paid payment with the wrong merchant
certificate returns exactly the same `Swoosh::PaymentNotFound`.

Retrying won't fix either case, but the right response differs, and you can't
tell them apart from the response alone. So don't write a 404 off as a payment
that never happened. Record it and alert when the rate climbs: a handful usually
means bad rows, while a spike almost always means a certificate or environment
mismatch, where every one of those payments is real.

`ServerError` (5xx) is separated from `RequestError` (4xx) so you retry the
failures worth retrying and nothing else.

### Payments don't expire out from under you

The three-minute limit is the payer's deadline to accept, not a retention
window. A payment request stays queryable long after it settles -- Swish rejects
an original as too old for refunds only past 13 months. Age alone will not turn a
poll into a 404.

### Staging settles payments for you

MSS moves a payment to `PAID` on its own, with no payer involved. Convenient for
exercising the happy path, but it means staging never shows you `DECLINED`, and
never shows you the `ERROR`/`TM01` timeout that a real unanswered payment
produces. Don't read "it went `PAID` in staging" as proof your flow handles the
other four statuses.

## What to persist

Just the id:

```ruby
add_column :orders, :swish_payment_id, :string
```

Everything else comes back from `find_payment`. The one exception is the
m-commerce token, which Swish returns once and never again -- so if you need it
in a later request (a reload, an AJAX-rendered QR), Swoosh can keep it for you:

```ruby
Swoosh.token_for(order.swish_payment_id)   # => token, or nil
```

`nil` means "create a fresh payment request", never an error -- whether the token
expired, was never stored, or was dropped because you cancelled the payment. In
Rails this is backed by `Rails.cache` by default with a 5 minute TTL, since the
token dies with the payment window anyway. Set `config.swoosh.token_store = nil` to turn it off.
Losing a token costs the payer one extra tap; nothing about it is load-bearing.

Statuses are deliberately **not** cached -- caching a `CREATED` would make your
poller report stale results for a payment that has already settled.

## Without Rails

Nothing in the core depends on Rails, so Sinatra, Hanami and plain Ruby work the
same way:

```ruby
Swoosh.configure do |config|
  config.environment   = :production
  config.cert_dir      = "config/certs"
  config.cert_password = ENV["SWISH_CERT_PASSWORD"]
  config.payee_alias   = "1231181189"
end

Swoosh.generate_payment(100, callback_url: "https://example.com/swish", message: "Kaffe")
```

## Development

    $ bin/setup
    $ bundle exec rake

`rake` runs two suites in separate processes: `rake test:gem` exercises the gem
with Rails absent from the process, and `rake test:rails` drives it through the
dummy application in `test/dummy`.

HTTP is recorded with VCR against the Swish staging playground. To re-record,
delete the cassette in `test/cassettes` and run the suite again.

### The certificate canaries

Four tests in `test/swoosh_test.rb` compare the bundled certificates against the
real clock, and they are meant to. They fail 30 days before a certificate lapses,
because a suite that stays green on an expired bundle would ship a staging
fallback that cannot complete a TLS handshake.

Don't freeze or travel time around them. When one fires, the message tells you
what to renew and where from. Nothing else in the suite depends on the clock.

## License

[MIT](https://opensource.org/licenses/MIT).
