# The message that proves a subscriber's address is theirs: one link back to
# this site, which is the whole confirmation flow.
#
# Plain text only. The body is one URL and a few sentences, every mail client
# auto-links a bare URL, and there is no subscriber-supplied content that
# could become markup in someone's inbox.
class SubscriptionConfirmationEmail < BaseEmail
  def initialize(@subscriber : Subscriber)
  end

  def to : Array(Carbon::Address)
    [Carbon::Address.new(@subscriber.email)]
  end

  def from : Carbon::Address
    # The address docs/user-guides/crystalbits.md already publishes for the
    # newsletter.
    Carbon::Address.new("CrystalBits", "newsletter@crystalbits.org")
  end

  def subject : String
    "Confirm your CrystalBits subscription"
  end

  def headers : Hash(String, String)
    # A one-click exit for anyone who never asked to be subscribed. The
    # unsubscribe action accepts the same token the confirm link carries.
    @headers["List-Unsubscribe"] = "<#{unsubscribe_url}>"
    @headers
  end

  def text_body : String
    <<-TEXT
    Someone, hopefully you, asked for the CrystalBits newsletter to be sent to
    this address.

    Confirm the subscription by opening this link:

    #{confirm_url}

    If it was not you, ignore this email. The address stays unconfirmed and
    no newsletter is sent to it.
    TEXT
  end

  private def confirm_url : String
    Newsletter::Confirm.with(confirmation_token).url
  end

  private def unsubscribe_url : String
    Newsletter::Unsubscribe.with(confirmation_token).url
  end

  private def confirmation_token : String
    @subscriber.confirmation_token ||
      raise "SubscriptionConfirmationEmail needs a confirmation token; subscriber ##{@subscriber.id} has none."
  end
end
