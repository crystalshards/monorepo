abstract class BrowserAction < Lucky::Action
  accepted_formats [:html]

  include Lucky::ProtectFromForgery
  include Lucky::SecureHeaders::DisableFLoC
  include Lucky::EnforceUnderscoredRoute
end
