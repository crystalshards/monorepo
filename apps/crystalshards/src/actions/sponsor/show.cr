class Sponsor::Show < BrowserAction
  # No query and no state of its own: the only input is the configured
  # funding destination, and when it is unset the page says sponsorship is
  # not open yet rather than rendering a dead button.
  get "/sponsor" do
    html Sponsor::ShowPage
  end
end
