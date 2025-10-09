class Newsletter::UnsubscribedPage < MainLayout
  needs subscriber : Subscriber

  def page_title
    "Unsubscribed"
  end

  def content
    div class: "unsubscribe-message" do
      h1 "You've Been Unsubscribed"

      para do
        text "You won't receive any more emails from CrystalBits newsletter."
      end

      para do
        text "Changed your mind? You can always subscribe again from our homepage."
      end

      div class: "unsubscribe-actions" do
        a href: "/", class: "btn-primary" do
          text "Back to Home"
        end
      end
    end
  end
end
