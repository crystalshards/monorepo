class Newsletter::ConfirmationSentPage < MainLayout
  def page_title
    "Confirmation Sent"
  end

  def content
    div class: "confirmation-message" do
      h1 "Check Your Email"

      para do
        text "We've sent you a confirmation email. Please click the link in the email to complete your subscription."
      end

      para do
        text "Didn't receive the email? Check your spam folder or "
        a href: "/", do: text("return to the homepage")
        text "."
      end
    end
  end
end
