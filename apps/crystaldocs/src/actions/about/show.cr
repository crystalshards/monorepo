class About::Show < BrowserAction
  # The masthead has always linked here. The page it promised did not exist,
  # so every "About" click on every page of the site was a 404.
  #
  # Static content, no query: a documentation host has to explain where its
  # documentation comes from, because the answer is the reason to trust it.
  get "/about" do
    html About::ShowPage
  end
end
