class Api::Newsletter::Subscriptions::Create < ApiAction
  include Api::Auth::SkipRequireAuthToken
  include Lucky::RateLimit
  rate_limit to: 10, within: 1.hour

  # The consumer is a plain HTML form on one of the other three sites,
  # rendered server side and working with JavaScript off, so this action
  # speaks form-encoded HTML, not JSON. No CSRF token exists for a
  # cross-origin form post; the forgery protection on BrowserAction is what
  # refuses those, and ApiAction does not include it. What keeps an open
  # mail-sending endpoint safe instead is the rate limit here and the
  # per-address bounds in CrystalBits::Subscriptions.
  accepted_formats [:html]

  # The bare client IP, without the ephemeral source port a Socket::IPAddress
  # carries: RemoteIpHandler sets remote_ip from X-Forwarded-For or the
  # socket peer. `remote_address.to_s` would bucket every connection of one
  # client separately, which is no limit at all. The fallback covers the
  # in-process spec client, which has neither.
  def rate_limit_identifier
    request.remote_ip.presence || "test:default"
  end

  post "/api/newsletter/subscriptions" do
    CrystalBits::Subscriptions.subscribe(params.get?(:email))

    # Every outcome lands on the same page. New address, known address,
    # confirmed address and junk are indistinguishable from the outside, so
    # the endpoint cannot be used to probe who is subscribed. The submitted
    # address is never rendered back.
    redirect to: ::Newsletter::ConfirmationSent
  end
end
