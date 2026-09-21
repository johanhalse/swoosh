# frozen_string_literal: true

# Exercises the gem the way a host application would: no explicit client and no
# merchant number at the call site -- just the callback this payment type wants.
class PaymentsController < ApplicationController
  CALLBACKS = {
    "order" => "https://dummy.test/swish/orders",
    "donation" => "https://dummy.test/swish/donations"
  }.freeze

  def create
    Swoosh.generate_payment(
      params[:amount].to_i,
      callback_url: CALLBACKS.fetch(params[:kind], CALLBACKS["order"]),
      message: params[:message],
      payee_payment_reference: params[:reference]
    )

    render json: { environment: Swoosh.configuration.environment, url: Swoosh.client.url }, status: :created
  end

  # Withdrawing an abandoned checkout. The two refusals need different answers,
  # which is the whole reason they are separate classes.
  def destroy
    payment = Swoosh.cancel_payment(params[:id])

    render json: { id: payment.id, status: payment.status }
  rescue Swoosh::PaymentAlreadyCancelled
    # Already where we wanted it. Nothing to do.
    head :no_content
  rescue Swoosh::PaymentNotCancellable => e
    # The payer accepted first, so this checkout is paid, not abandoned.
    render json: { error: e.error_code }, status: :conflict
  end
end
