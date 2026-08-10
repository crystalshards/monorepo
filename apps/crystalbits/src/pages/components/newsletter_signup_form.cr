class NewsletterSignupForm < Lucky::BaseComponent
  needs inline : Bool = false
  # Renders under an h2 section on the homepage and under the h2 CTA on post
  # pages, so the caller sets the level rather than baking it into the style.
  needs heading_level : Int32 = 2
  # Ids must be unique when the form appears more than once on a page.
  needs field_id : String = "newsletter-email"

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
      tag "h#{@heading_level}" do
        text "Subscribe to CrystalBits Newsletter"
      end
      para "Get the latest Crystal tutorials, news, and updates delivered to your inbox."
    end

    # form_for emits Lucky's authenticity token. A raw form tag does not, and
    # Lucky::ProtectFromForgery rejects the POST with 403.
    form_for Newsletter::Subscribe, class: "newsletter-form" do
      # A placeholder is not a label: it vanishes on input and is not a
      # dependable accessible name (WCAG 3.3.2). The field name is load
      # bearing: SaveSubscriber reads the nested subscriber param, and any
      # other name raises Avram::Params#nested and returns HTTP 400.
      label "Email address", for: @field_id, class: "visually-hidden"
      tag "input", type: "email", id: @field_id, name: "subscriber:email", placeholder: "your@email.com", required: "true", class: "newsletter-input"
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
      label "Email address", for: @field_id, class: "visually-hidden"
      tag "input", type: "email", id: @field_id, name: "subscriber:email", placeholder: "your@email.com", required: "true", class: "newsletter-input-inline"
      button type: "submit", class: "newsletter-button-inline" do
        text "Subscribe"
      end
    end
  end
end
