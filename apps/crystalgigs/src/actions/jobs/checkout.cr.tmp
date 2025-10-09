class Jobs::Checkout < BrowserAction
  post "/jobs/:job_id/checkout" do
    job = JobQuery.new.find(job_id)
    payment_method_id = params.get("payment_method_id")

    if job.published_at
      flash.info = "This job has already been published"
      redirect to: Jobs::Show.with(job.id)
    else
      begin
        process_payment(job, payment_method_id)

        SaveJob.update!(job,
          published_at: Time.utc,
          expires_at: Time.utc + 30.days,
          active: true
        )

        flash.success = "Payment successful! Your job has been published."
        redirect to: Jobs::Show.with(job.id)
      rescue ex : Stripe::StripeException
        Log.error { "Stripe payment failed: #{ex.message}" }
        flash.failure = "Payment failed: #{ex.message}"
        redirect to: Jobs::Payment.with(job.id)
      rescue ex
        Log.error { "Payment processing error: #{ex.message}" }
        flash.failure = "An error occurred processing your payment. Please try again."
        redirect to: Jobs::Payment.with(job.id)
      end
    end
  end

  private def process_payment(job : Job, payment_method_id : String)
    Stripe.api_key = ENV["STRIPE_SECRET_KEY"]

    payment_intent = Stripe::PaymentIntent.create(
      amount: 9900_i64,
      currency: "usd",
      payment_method: payment_method_id,
      confirm: true,
      automatic_payment_methods: {
        enabled:         true,
        allow_redirects: "never",
      },
      metadata: {
        job_id:       job.id.to_s,
        company_name: job.company_name,
        job_title:    job.title,
      },
      description: "Job posting: #{job.title} at #{job.company_name}"
    )

    unless payment_intent.status == "succeeded"
      raise Stripe::StripeException.new("Payment not successful")
    end

    Log.info { "Payment successful for job #{job.id}: #{payment_intent.id}" }
  end
end
