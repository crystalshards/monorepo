class Jobs::PaymentPage < MainLayout
  needs job : Job

  def page_title
    "Complete Payment"
  end

  def content
    section class: "page-header" do
      h1 do
        text "Complete Your Job Posting"
      end
    end

    section class: "payment-section" do
      div class: "payment-container" do
        div class: "payment-preview" do
          h2 do
            text "Job Preview"
          end

          div class: "preview-card" do
            mount JobCard, job: @job
          end

          a href: "/jobs/#{@job.id}/edit", class: "button button-secondary" do
            text "Edit Job Details"
          end
        end

        div class: "payment-form-container" do
          h2 do
            text "Payment Details"
          end

          div class: "pricing-summary" do
            div class: "pricing-row" do
              span do
                text "#{Pricing.duration_days}-day job posting"
              end
              strong do
                text "#{Pricing.price_label}.00"
              end
            end
            div class: "pricing-row pricing-total" do
              span do
                text "Total"
              end
              strong do
                text "#{Pricing.price_label}.00 #{Pricing::CURRENCY.upcase}"
              end
            end
          end

          if Payments.disabled?
            render_payments_disabled_form
          else
            render_stripe_form
          end

          div class: "payment-security" do
            para class: "security-note" do
              text "Secure payment powered by Stripe"
            end
            para class: "security-note" do
              text "Your payment information is encrypted and secure"
            end
          end
        end
      end
    end

    unless Payments.disabled?
      script src: "https://js.stripe.com/v3/" do
      end

      script do
        raw stripe_initialization_script
      end
    end
  end

  private def render_payments_disabled_form
    div class: "payment-disabled-notice" do
      para do
        text "Payment processing is disabled in this environment. Publishing this job will not charge anything."
      end
    end

    form_for Jobs::Checkout.with(job_id: @job.id), class: "job-form" do
      button type: "submit", id: "submit-payment", class: "button button-primary button-large" do
        text "Publish Job (no charge)"
      end
    end
  end

  private def render_stripe_form
    div id: "payment-form" do
      form_for Jobs::Checkout.with(job_id: @job.id), id: "stripe-payment-form" do
        div id: "card-element" do
        end

        div id: "card-errors", role: "alert" do
        end

        button type: "submit", id: "submit-payment", class: "button button-primary button-large" do
          text "Pay #{Pricing.price_label} & Publish Job"
        end
      end
    end
  end

  private def stripe_initialization_script
    <<-JAVASCRIPT
      (function() {
        var stripe = Stripe('#{stripe_publishable_key}');
        var elements = stripe.elements();
        var cardElement = elements.create('card', {
          style: {
            base: {
              fontSize: '16px',
              color: '#32325d',
              fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif',
              '::placeholder': {
                color: '#aab7c4'
              }
            },
            invalid: {
              color: '#fa755a',
              iconColor: '#fa755a'
            }
          }
        });

        cardElement.mount('#card-element');

        cardElement.on('change', function(event) {
          var displayError = document.getElementById('card-errors');
          if (event.error) {
            displayError.textContent = event.error.message;
          } else {
            displayError.textContent = '';
          }
        });

        var form = document.getElementById('stripe-payment-form');
        form.addEventListener('submit', async function(event) {
          event.preventDefault();

          var submitButton = document.getElementById('submit-payment');
          submitButton.disabled = true;
          submitButton.textContent = 'Processing...';

          const {paymentMethod, error} = await stripe.createPaymentMethod({
            type: 'card',
            card: cardElement,
          });

          if (error) {
            var errorElement = document.getElementById('card-errors');
            errorElement.textContent = error.message;
            submitButton.disabled = false;
            submitButton.textContent = 'Pay $99 & Publish Job';
          } else {
            var hiddenInput = document.createElement('input');
            hiddenInput.setAttribute('type', 'hidden');
            hiddenInput.setAttribute('name', 'payment_method_id');
            hiddenInput.setAttribute('value', paymentMethod.id);
            form.appendChild(hiddenInput);
            form.submit();
          }
        });
      })();
    JAVASCRIPT
  end

  private def stripe_publishable_key : String
    Payments.publishable_key
  end
end
