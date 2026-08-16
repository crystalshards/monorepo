class Newsletter::Subscribe < BrowserAction
  post "/newsletter/subscribe" do
    # The same flow the cross-origin API action runs: one store, one
    # validation path, one confirmation send, and the same per-address bounds.
    result = CrystalBits::Subscriptions.subscribe(params.nested?(:subscriber)["email"]?)

    if result.invalid?
      # Junk is the one outcome a same-origin reader is told about: the fix
      # is theirs to make. Subscription state is never part of the answer.
      flash.failure = "Could not subscribe. Please check your email address."
      redirect_back fallback: Home::Index
    else
      flash.success = "Please check your email to confirm your subscription."
      redirect to: Newsletter::ConfirmationSent
    end
  end
end
