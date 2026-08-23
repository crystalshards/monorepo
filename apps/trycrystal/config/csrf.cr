# CSRF Protection Configuration
#
# Disable CSRF protection in test environment to allow tests to POST
# without providing CSRF tokens. In production and development, CSRF
# protection is enabled by default.

Lucky::ProtectFromForgery.configure do |settings|
  settings.allow_forgery_protection = !LuckyEnv.test?
end
