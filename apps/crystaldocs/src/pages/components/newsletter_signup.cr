# The newsletter signup. This site renders the form and nothing else: the
# post goes straight to CrystalBits, which owns the subscriber store, the
# confirmation email and the rate limits. The action is built from SiteLinks
# so it always points at this environment's CrystalBits, never a literal
# host. No CSRF token exists for a cross-origin form post; the endpoint is
# the one that exists to accept them. No JavaScript: the form works without
# it, and there is nothing here for a script to enhance.
class Components::NewsletterSignup < Lucky::BaseComponent
  def render
    div class: "newsletter-signup" do
      h2 "The CrystalBits newsletter", class: "newsletter-signup-title"
      para class: "newsletter-signup-copy" do
        text "Crystal tutorials, release news and community writing. One email when there is something new, never a stream."
      end

      form action: subscribe_url, method: "post", class: "newsletter-signup-form" do
        # A placeholder is not a label: it vanishes on input and is not a
        # dependable accessible name (WCAG 3.3.2). The field name is load
        # bearing: the CrystalBits endpoint reads exactly `email`.
        label "Email address", for: "newsletter-email", class: "visually-hidden"
        input(
          type: "email",
          id: "newsletter-email",
          name: "email",
          placeholder: "you@example.com",
          required: "true",
          class: "newsletter-signup-input"
        )
        button type: "submit", class: "newsletter-signup-button" do
          tag "i", class: "fa-solid fa-envelope", "aria-hidden": "true"
          text " Subscribe"
        end
      end

      para class: "newsletter-signup-note" do
        text "You will get one confirmation email to check the address is yours. Unsubscribe any time."
      end
    end
  end

  private def subscribe_url : String
    "#{SiteLinks.origin(:crystalbits)}/api/newsletter/subscriptions"
  end
end
