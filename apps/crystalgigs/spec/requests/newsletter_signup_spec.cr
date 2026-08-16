require "../spec_helper"

# The signup form is this site's half of the cross-site newsletter flow: it
# posts the reader's address straight to CrystalBits, which owns the
# subscriber store and the confirmation email.
describe "Newsletter signup" do
  it "renders an email form whose action is the configured CrystalBits origin" do
    response = BrowserClient.exec(Home::Index)

    response.status_code.should eq(200)

    form = response.body.match!(/<form[^>]*class="newsletter-signup-form"[^>]*>/)[0]
    form.should contain(%(method="post"))
    # Built from SiteLinks, never a literal host: this fails the way it
    # should if the form ever hardcodes a production origin, because the spec
    # environment's CrystalBits origin is a localhost one.
    form.should contain(%(action="#{SiteLinks.origin(:crystalbits)}/api/newsletter/subscriptions"))

    field = response.body.match!(/<input[^>]*type="email"[^>]*>/)[0]
    field.should contain(%(name="email"))
    field.should contain(%(required))
  end

  it "labels the email field accessibly" do
    body = BrowserClient.exec(Home::Index).body

    # The placeholder is not the label: a visually hidden label element names
    # the field for assistive technology (WCAG 3.3.2).
    body.should contain(%(for="newsletter-email"))
    field = body.match!(/<input[^>]*type="email"[^>]*>/)[0]
    field.should contain(%(id="newsletter-email"))
  end
end
