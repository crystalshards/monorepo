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
                text "30-day job posting"
              end
              strong do
                text "$99.00"
              end
            end
            div class: "pricing-row pricing-total" do
              span do
                text "Total"
              end
              strong do
                text "$99.00 USD"
              end
            end
          end

          div id: "payment-form" do
            form_tag action: "/jobs/#{@job.id}/checkout", method: "post", id: "stripe-payment-form" do
              div id: "card-element" do
              end

              div id: "card-errors", role: "alert" do
              end

              button type: "submit", id: "submit-payment", class: "button button-primary button-large" do
                text "Pay $99 & Publish Job"
              end
            end
          end

          div class: "payment-security" do
            para class: "security-note" do
              text "🔒 Secure payment powered by Stripe"
            end
            para class: "security-note" do
              text "Your payment information is encrypted and secure"
            end
          end
        end
      end
    end

    script src: "https://js.stripe.com/v3/" do
    end

    script do
      raw stripe_initialization_script
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
    ENV["STRIPE_PUBLISHABLE_KEY"]? || "pk_test_placeholder"
  end
end
