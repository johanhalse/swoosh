# frozen_string_literal: true

# What a host app writes: include the concern, act on the verified payment.
module Swish
  class CallbacksController < ApplicationController
    include Swoosh::Callback::Controller
    skip_forgery_protection

    def create
      payment = swoosh_verified_payment
      Rails.configuration.x.settled_payments << payment.id if payment.paid?

      render json: { id: payment.id, status: payment.status, claimed: swoosh_callback.status }
    end
  end
end
