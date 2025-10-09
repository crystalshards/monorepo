class Newsletter::Subscribe < BrowserAction
  post "/newsletter/subscribe" do
    SaveSubscriber.create(params) do |operation, subscriber|
      if subscriber
        flash.success = "Please check your email to confirm your subscription."
        redirect to: Newsletter::ConfirmationSent
      else
        flash.failure = "Could not subscribe. Please check your email address."
        redirect_back fallback: Home::Index
      end
    end
  end
end
