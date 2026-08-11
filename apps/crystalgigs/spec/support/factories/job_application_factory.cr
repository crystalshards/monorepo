class JobApplicationFactory < Avram::Factory
  def initialize
    candidate_name "Ada Lovelace"
    candidate_email "#{sequence("candidate")}@example.com"
    resume_url "https://example.com/resumes/ada.pdf"
    cover_letter "I have been writing Crystal since before it compiled."
    handoff_status JobApplication::STATUS_PENDING
  end
end
