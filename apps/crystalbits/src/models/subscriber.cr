class Subscriber < BaseModel
  table do
    column email : String
    column confirmed : Bool = false
    column confirmation_token : String?
    column confirmed_at : Time?
    column unsubscribed_at : Time?
  end

  def active? : Bool
    confirmed && unsubscribed_at.nil?
  end

  def generate_confirmation_token
    self.confirmation_token = Random::Secure.hex(32)
  end
end
