class AtsConnectionQuery < AtsConnection::BaseQuery
  def active_only
    active(true)
  end

  def for_user(user : User)
    user_id(user.id)
  end

  def for_board(provider : String, board_token : String)
    self.provider(provider.strip.downcase).board_token(board_token.strip)
  end

  def recent
    order_by(:created_at, :desc)
  end
end
