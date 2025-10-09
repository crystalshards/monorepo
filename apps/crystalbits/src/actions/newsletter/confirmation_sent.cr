class Newsletter::ConfirmationSent < BrowserAction
  get "/newsletter/confirmation_sent" do
    html ConfirmationSentPage
  end
end
