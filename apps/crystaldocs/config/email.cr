# This app sends no mail, in any environment, and therefore asks for no mail
# credential.
#
# It used to hard-exit at boot in production without SEND_GRID_KEY, which meant
# the documentation site would refuse to serve a single page because a
# credential it has no use for was absent. That is the wrong failure: the blast
# radius of a missing mail key should be mail, not the site.
#
# The scaffold this replaced suggested setting the variable to the string
# 'unused' to get past the check. Do not reintroduce that, here or anywhere. A
# sentinel credential is indistinguishable from a real one to everything
# downstream, and it is how a values file ended up pinning four secrets to
# "unused" and silently overriding what CI passed. If a service needs a key it
# fails closed and names it; if it does not need one it does not ask.
#
# If this app ever does need to send, add the SendGrid adapter back together
# with the code that sends, and make the key required at that point.
BaseEmail.configure do |settings|
  settings.adapter =
    if LuckyEnv.development?
      Carbon::DevAdapter.new(print_emails: true)
    else
      Carbon::DevAdapter.new
    end
end
