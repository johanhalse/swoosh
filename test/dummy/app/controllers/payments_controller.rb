# frozen_string_literal: true

# Exercises the gem the way a host application would: no explicit client, no
# certificate paths -- just Swoosh.generate_payment off the railtie's config.
class PaymentsController < ApplicationController
  def create
    Swoosh.generate_payment(params[:amount].to_i, params[:message])

    render json: { environment: Swoosh.configuration.environment, url: Swoosh.client.url }, status: :created
  end
end
