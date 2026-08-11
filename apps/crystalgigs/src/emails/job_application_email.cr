# Hands an application to an employer whose ATS has no application API, or
# whose API we are not configured to call.
#
# Plain text only: the body carries candidate-supplied content, and text is
# the one format where that content cannot become markup in a recruiter's
# inbox. Replies go straight to the candidate.
class JobApplicationEmail < BaseEmail
  def initialize(
    @job : Job,
    @application : JobApplication,
    @recipient : String,
    @sender : String,
  )
  end

  def to : Array(Carbon::Address)
    [Carbon::Address.new(@recipient)]
  end

  def from : Carbon::Address
    Carbon::Address.new(@sender)
  end

  def subject : String
    "New application: #{@application.candidate_name} for #{@job.title}"
  end

  def headers : Hash(String, String)
    @headers["Reply-To"] = @application.candidate_email
    @headers
  end

  def text_body : String
    String.build do |io|
      io << "A candidate applied through CrystalGigs.\n\n"
      io << "Position: " << @job.title << '\n'
      io << "Company:  " << @job.company_name << '\n'
      io << "Name:     " << @application.candidate_name << '\n'
      io << "Email:    " << @application.candidate_email << '\n'

      if phone = @application.candidate_phone
        io << "Phone:    " << phone << '\n' unless phone.blank?
      end

      if resume_url = @application.resume_url
        io << "Resume:   " << resume_url << '\n' unless resume_url.blank?
      end

      if cover_letter = @application.cover_letter
        unless cover_letter.blank?
          io << "\nCover letter\n------------\n" << cover_letter << '\n'
        end
      end

      io << "\nReply to this message to reach the candidate directly.\n"
    end
  end
end
