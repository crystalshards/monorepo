class Newsletter::ConfirmedPage < MainLayout
  needs subscriber : Subscriber

  def page_title
    "Subscription Confirmed"
  end

  def content
    div class: "confirmation-success" do
      h1 "✓ You're Subscribed!"

      para do
        text "Your subscription to CrystalBits newsletter is confirmed. We'll send you the latest Crystal tutorials, news, and updates."
      end

      para do
        text "Your email: "
        strong { text @subscriber.email }
      end

      div class: "confirmation-actions" do
        a href: "/", class: "btn-primary" do
          text "Back to Home"
        end

        a href: "/posts", class: "btn-secondary" do
          text "Browse Posts"
        end
      end
    end
  end
end
