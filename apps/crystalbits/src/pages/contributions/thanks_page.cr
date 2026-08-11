class Contributions::ThanksPage < MainLayout
  def page_title
    "Thanks for the submission"
  end

  def content
    section class: "contribute-thanks" do
      h1 "Got it, thank you"

      para class: "contribute-lede" do
        text "Your draft is in the review queue. It is stored as a submission " \
             "and it is not public."
      end

      h2 "What happens now"

      ol do
        li "An editor reads it. A person, not a script."
        li "If we publish it, it goes up under your name, with your canonical link if you gave one."
        li "If we do not, we will tell you why on the contact you left."
      end

      para do
        text "In the meantime, "
        a href: "/news" do
          text "see what else is up"
        end
        text " or "
        a href: "/contribute" do
          text "send another one"
        end
        text "."
      end
    end
  end
end
