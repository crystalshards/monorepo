class Jobs::Checkout < BrowserAction
  post "/jobs/:job_id/checkout" do
    job = JobQuery.new.find(job_id)

    if job.published_at
      flash.info = "This job has already been published"
      redirect to: Jobs::Show.with(job.id)
      return
    end

    payment_method_id = params.get("payment_method_id")

    begin
      require "stripe"

      Stripe.api_key = ENV["STRIPE_SECRET_KEY"]? || "sk_test_placeholder"

      payment_intent = Stripe::PaymentIntent.create(
        amount: 9900,
        currency: "usd",
        payment_method: payment_method_id,
        confirm: true,
        automatic_payment_methods: {
          enabled: true,
          allow_redirects: "never",
        },
        metadata: {
          job_id: job.id.to_s,
          job_title: job.title,
          company_name: job.company_name,
        },
      )

      if payment_intent.status == "succeeded"
        job.published_at = Time.utc
        job.active = true
        job.save!

        flash.success = "Payment successful! Your job posting is now live."
        redirect to: Jobs::Show.with(job.id)
      else
        flash.failure = "Payment failed. Please try again."
        redirect to: Jobs::Payment.with(job.id)
      end
    rescue ex : Exception
      flash.failure = "Payment error: #{ex.message}"
      redirect to: Jobs::Payment.with(job.id)
    end
  end
end
