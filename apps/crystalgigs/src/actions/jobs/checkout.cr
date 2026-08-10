class Jobs::Checkout < BrowserAction
  post "/jobs/:job_id/checkout" do
    job = JobQuery.new.find(job_id)

    if job.published_at
      flash.info = "This job has already been published"
      redirect to: Jobs::Show.with(job.id)
    elsif Payments.disabled?
      publish(job)
      flash.success = "Job published. Payments are disabled in this environment, so no charge was made."
      redirect to: Jobs::Show.with(job.id)
    else
      charge_then_publish(job)
    end
  end

  private def charge_then_publish(job : Job)
    payment_method_id = params.get?("payment_method_id")

    if payment_method_id.nil? || payment_method_id.blank?
      flash.failure = "Payment details are missing. Please try again."
      return redirect to: Jobs::Payment.with(job.id)
    end

    intent = Stripe::PaymentIntent.create(
      amount: Pricing::PRICE_CENTS,
      currency: Pricing::CURRENCY,
      payment_method: payment_method_id,
      confirm: true,
      description: "CrystalGigs job posting: #{job.title}",
      metadata: {"job_id" => job.id.to_s, "company_name" => job.company_name}
    )

    if intent.status.try(&.succeeded?)
      publish(job)
      flash.success = "Payment successful. Your job posting is now live."
      redirect to: Jobs::Show.with(job.id)
    else
      flash.failure = "Payment was not completed. Please try again."
      redirect to: Jobs::Payment.with(job.id)
    end
  rescue error : Stripe::Error
    flash.failure = "Payment failed: #{error.message}"
    redirect to: Jobs::Payment.with(job.id)
  rescue IO::Error
    flash.failure = "Could not reach the payment processor. Please try again."
    redirect to: Jobs::Payment.with(job.id)
  end

  private def publish(job : Job)
    SaveJob.update!(
      job,
      published_at: Time.utc,
      expires_at: Time.utc + Pricing::DURATION,
      active: true
    )
  end
end
