require "../src/emails/carbon_resend_adapter"

# This app sends mail: CrystalBits is a newsletter, so delivery is the product.
# It still is not a reason to refuse to serve the site.
#
# Without RESEND_API_KEY, production gets `Carbon::ResendAdapter::Unavailable`:
# the site boots and serves normally, and any attempt to send raises naming the
# variable. Mail is a feature, so the feature fails closed and the process does
# not. Adding the key is the whole switch; no code changes with it.
#
# What is deliberately not offered is a way to make a send look like it worked.
# The scaffold this replaced told the operator to set the mail key to the
# string 'unused' to get past a boot check, and that suggestion is removed
# rather than reworded. A sentinel credential is indistinguishable from a real
# one to everything downstream, so the app reports healthy, accepts subscribers
# and sends nothing. For a newsletter that failure is invisible from the inside
# and total from the outside. The same objection rules out falling back to
# `Carbon::DevAdapter` here: it returns success for a message it never sent.
BaseEmail.configure do |settings|
  if LuckyEnv.production?
    settings.adapter = Carbon::ResendAdapter.from_env("the CrystalBits newsletter")
  elsif LuckyEnv.development?
    settings.adapter = Carbon::DevAdapter.new(print_emails: true)
  else
    settings.adapter = Carbon::DevAdapter.new
  end
end
