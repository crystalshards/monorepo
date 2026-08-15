class Jobs::Show < BrowserAction
  get "/jobs/:job_id" do
    job = JobQuery.new.find(job_id)

    if job.published? && !job.open?
      # It went live once and is not open now (expired past its paid window,
      # or delisted because the employer's own board no longer carries it).
      # Leaving the page rendering as though nothing had changed - Apply Now
      # button included - would misrepresent a closed role to every human
      # who still has the link, and Google's own docs list exactly this as a
      # policy violation ("Expired jobs are still live... the page is still
      # live"). Gone is the honest, permanent answer: this used to be here
      # and is not coming back, for a person and a crawler alike. It is also
      # one of the two ways Google's own docs say to retire a listing - the
      # other, stamping `validThrough` in the past while leaving the page
      # up, keeps advertising a closed role to every human visitor.
      plain_text "This job posting is no longer available.", status: 410
    else
      html Jobs::ShowPage, job: job
    end
  end
end
