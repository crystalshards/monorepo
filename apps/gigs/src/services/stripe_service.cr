require "stripe"
require "json"

module CrystalGigs
  class StripeService
    # Job posting pricing
    JOB_POSTING_PRICE = 9900 # $99.00 in cents
    CURRENCY = "usd"
    
    def self.create_payment_intent(job_data : Hash(String, String))
      begin
        # Create payment intent with Stripe
        payment_intent = Stripe::PaymentIntent.create({
          amount: JOB_POSTING_PRICE,
          currency: CURRENCY,
          automatic_payment_methods: {
            enabled: true
          },
          metadata: {
            job_title: job_data["title"]? || "",
            company: job_data["company"]? || "",
            email: job_data["email"]? || ""
          }
        })
        
        {
          client_secret: payment_intent.client_secret,
          payment_intent_id: payment_intent.id
        }
      rescue ex : Exception
        puts "Stripe error: #{ex.message}"
        nil
      end
    end
    
    def self.confirm_payment(payment_intent_id : String)
      begin
        payment_intent = Stripe::PaymentIntent.retrieve(payment_intent_id)
        payment_intent.status == "succeeded"
      rescue ex : Exception
        puts "Error confirming payment: #{ex.message}"
        false
      end
    end
    
    def self.get_payment_intent(payment_intent_id : String)
      begin
        Stripe::PaymentIntent.retrieve(payment_intent_id)
      rescue ex : Exception
        puts "Error retrieving payment intent: #{ex.message}"
        nil
      end
    end
    
    def self.create_checkout_session(job_data : Hash(String, String), success_url : String, cancel_url : String)
      begin
        session = Stripe::Checkout::Session.create({
          payment_method_types: ["card"],
          line_items: [{
            price_data: {
              currency: CURRENCY,
              product_data: {
                name: "Job Posting - #{job_data["title"]? || "Crystal Developer Role"}",
                description: "30-day featured job posting on CrystalGigs.com"
              },
              unit_amount: JOB_POSTING_PRICE
            },
            quantity: 1
          }],
          mode: "payment",
          success_url: success_url,
          cancel_url: cancel_url,
          metadata: {
            job_title: job_data["title"]? || "",
            company: job_data["company"]? || "",
            location: job_data["location"]? || "",
            job_type: job_data["type"]? || "",
            salary: job_data["salary"]? || "",
            description: job_data["description"]? || "",
            email: job_data["email"]? || "",
            website: job_data["website"]? || ""
          }
        })
        
        {
          checkout_url: session.url,
          session_id: session.id
        }
      rescue ex : Exception
        puts "Error creating checkout session: #{ex.message}"
        nil
      end
    end
    
    def self.retrieve_session(session_id : String)
      begin
        Stripe::Checkout::Session.retrieve(session_id)
      rescue ex : Exception
        puts "Error retrieving session: #{ex.message}"
        nil
      end
    end
  end
end