# frozen_string_literal: true

require_relative "../callback"

module Swoosh
  module Callback
    # The Rails half: nothing but the glue that hands Swoosh::Callback the raw
    # body. All the behaviour lives in the plain module.
    #
    #   class Swish::CallbacksController < ApplicationController
    #     include Swoosh::Callback::Controller
    #     skip_forgery_protection
    #
    #     def create
    #       payment = swoosh_verified_payment
    #       Order.find_by!(swish_payment_id: payment.id).settle!(payment) if payment.paid?
    #       head :ok
    #     end
    #   end
    module Controller
      include Swoosh::Callback

      private

      def swoosh_callback_body
        request.body.rewind if request.body.respond_to?(:rewind)
        request.body.read
      end
    end
  end
end
