# Mounted only from `Jobs::ShowPage`. Google's own guidance is explicit that
# `JobPosting` markup belongs only on "the most detailed leaf page possible"
# for a single job, never on a page that lists several - see the "wrong
# page" entry in Google's troubleshooting docs - so this has no business
# being mounted from `Jobs::IndexPage` or anywhere else jobs are listed.
class JobPostingJsonLd < Lucky::BaseComponent
  needs job : Job

  def render
    return unless @job.open?

    script type: "application/ld+json" do
      raw JobPostingSchema.new(@job).to_html_safe_json
    end
  end
end
