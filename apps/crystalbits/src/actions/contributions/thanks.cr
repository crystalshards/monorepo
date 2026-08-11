class Contributions::Thanks < BrowserAction
  get "/contributions/thanks" do
    html Contributions::ThanksPage
  end
end
