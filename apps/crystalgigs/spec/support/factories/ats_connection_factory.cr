class AtsConnectionFactory < Avram::Factory
  def initialize
    user_id UserFactory.create.id
    provider "greenhouse"
    board_token sequence("board-token")
    company_name "Crystal Corp"
    company_url "https://crystalcorp.example.com"
    active true
  end
end
