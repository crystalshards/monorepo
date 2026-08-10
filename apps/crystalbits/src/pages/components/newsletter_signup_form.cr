class NewsletterSignupForm < Lucky::BaseComponent
  needs inline : Bool = false

  def render
    div class: newsletter_class do
      if @inline
        render_inline_form
      else
        render_full_form
      end
    end
  end

  private def newsletter_class
    @inline ? "newsletter-signup-inline" : "newsletter-signup"
  end

  private def render_full_form
    div class: "newsletter-header" do
      h2 "Subscribe to CrystalBits Newsletter"
      para "Get the latest Crystal tutorials, news, and updates delivered to your inbox."
    end

    # form_for emits Lucky's authenticity token. A raw form tag does not, and
    # Lucky::ProtectFromForgery rejects the POST with 403.
    form_for Newsletter::Subscribe, class: "newsletter-form" do
      tag "input", type: "email", name: "subscriber:email", placeholder: "your@email.com", required: "true", class: "newsletter-input"
      button type: "submit", class: "newsletter-button" do
        text "Subscribe"
      end
    end

    para class: "newsletter-note" do
      text "We respect your privacy. Unsubscribe at any time."
    end
  end

  private def render_inline_form
    form_for Newsletter::Subscribe, class: "newsletter-form-inline" do
      tag "input", type: "email", name: "subscriber:email", placeholder: "your@email.com", required: "true", class: "newsletter-input-inline"
      button type: "submit", class: "newsletter-button-inline" do
        text "Subscribe"
      end
    end
  end
end
