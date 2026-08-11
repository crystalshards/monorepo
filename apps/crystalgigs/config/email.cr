require "carbon_sendgrid_adapter"

# This app sends mail: a job application handed off to an employer goes out by
# email when no ATS endpoint is configured. So the credential is genuinely
# required in production and its absence is a boot failure, loudly, naming the
# variable.
#
# There is deliberately no way to opt out. The scaffold this replaced told the
# operator to set SEND_GRID_KEY to the string 'unused' to get past the check,
# and that suggestion is removed rather than reworded. A sentinel credential is
# indistinguishable from a real one to everything downstream, so the app boots,
# reports healthy, accepts applications and drops every one of them on the
# floor. Failing to start is the honest outcome, because an application that is
# silently never delivered is worse than a service that never came up.
BaseEmail.configure do |settings|
  if LuckyEnv.production?
    settings.adapter = Carbon::SendGridAdapter.new(api_key: send_grid_key_from_env)
  elsif LuckyEnv.development?
    settings.adapter = Carbon::DevAdapter.new(print_emails: true)
  else
    settings.adapter = Carbon::DevAdapter.new
  end
end

private def send_grid_key_from_env
  ENV["SEND_GRID_KEY"]?.presence || raise_missing_key_message
end

# `.presence` above, not just `[]?`: an empty secret version is the shape this
# actually fails in, and an empty string would otherwise be accepted as a key
# and rejected later by SendGrid on every send.
private def raise_missing_key_message
  puts "Missing SEND_GRID_KEY. CrystalGigs delivers job applications by email and will not start without it. Set SEND_GRID_KEY to a real SendGrid API key.".colorize.red
  exit(1)
end
