# Include modules and add methods that are for all API requests.
#
# Deliberately no cookies and no session: the console holds its own state in
# the browser, and an endpoint that sets no cookie is an endpoint CSRF
# cannot touch. That is also why ApiAction does not include
# Lucky::ProtectFromForgery, unlike BrowserAction.
abstract class ApiAction < Lucky::Action
  disable_cookies
  accepted_formats [:json]
end
