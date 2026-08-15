require "../spec_helper"

describe JobPostingSchema do
  describe "#initialize" do
    it "raises for a job that has never been published" do
      job = JobFactory.create &.published_at(nil)

      expect_raises(ArgumentError, /open/) do
        JobPostingSchema.new(job)
      end
    end

    it "raises for a job that is past its paid window" do
      job = JobFactory.create &.published_at(Time.utc - 40.days).expires_at(Time.utc - 1.day)

      expect_raises(ArgumentError) do
        JobPostingSchema.new(job)
      end
    end

    it "raises for a delisted job" do
      job = JobFactory.create &.published_at(Time.utc).active(false)

      expect_raises(ArgumentError) do
        JobPostingSchema.new(job)
      end
    end

    it "accepts a published, active, unexpired job" do
      job = JobFactory.create &.published_at(Time.utc).expires_at(Time.utc + 1.day).active(true)

      JobPostingSchema.new(job).to_json.should contain("JobPosting")
    end
  end

  describe "#to_json" do
    it "maps every accepted job_type to Google's vocabulary" do
      mapping = {
        "full-time"  => "FULL_TIME",
        "part-time"  => "PART_TIME",
        "contract"   => "CONTRACTOR",
        "freelance"  => "CONTRACTOR",
        "internship" => "INTERN",
      }

      mapping.each do |job_type, expected|
        job = JobFactory.create &.job_type(job_type).published_at(Time.utc).active(true)
        parsed = JSON.parse(JobPostingSchema.new(job).to_json)

        parsed["employmentType"].as_s.should eq(expected)
      end
    end

    it "quotes a salaried engagement annually and an hourly-style engagement by the hour" do
      full_time = JobFactory.create &.job_type("full-time").salary_min(120_000).salary_max(nil)
        .published_at(Time.utc).active(true)
      contract = JobFactory.create &.job_type("contract").salary_min(80).salary_max(120)
        .published_at(Time.utc).active(true)

      full_time_json = JSON.parse(JobPostingSchema.new(full_time).to_json)
      contract_json = JSON.parse(JobPostingSchema.new(contract).to_json)

      full_time_json["baseSalary"]["value"]["unitText"].as_s.should eq("YEAR")
      full_time_json["baseSalary"]["value"]["minValue"].as_i.should eq(120_000)
      full_time_json["baseSalary"]["value"].as_h.has_key?("maxValue").should be_false

      contract_json["baseSalary"]["value"]["unitText"].as_s.should eq("HOUR")
    end

    it "omits baseSalary entirely when the row carries no pay" do
      job = JobFactory.create &.salary_min(nil).salary_max(nil).published_at(Time.utc).active(true)

      parsed = JSON.parse(JobPostingSchema.new(job).to_json)

      parsed.as_h.has_key?("baseSalary").should be_false
    end

    it "recognises a real USPS state code and nothing else" do
      recognised = JobFactory.create &.location("Detroit, MI").remote(false)
        .published_at(Time.utc).active(true)
      lowercase = JobFactory.create &.location("Detroit, mi").remote(false)
        .published_at(Time.utc).active(true)
      unrecognised = JobFactory.create &.location("Berlin, Germany").remote(false)
        .published_at(Time.utc).active(true)
      blank = JobFactory.create &.location(nil).remote(false)
        .published_at(Time.utc).active(true)

      recognised_json = JSON.parse(JobPostingSchema.new(recognised).to_json)
      lowercase_json = JSON.parse(JobPostingSchema.new(lowercase).to_json)
      unrecognised_json = JSON.parse(JobPostingSchema.new(unrecognised).to_json)
      blank_json = JSON.parse(JobPostingSchema.new(blank).to_json)

      recognised_json["jobLocation"]["address"]["addressRegion"].as_s.should eq("MI")
      recognised_json["jobLocation"]["address"]["addressCountry"].as_s.should eq("US")
      lowercase_json["jobLocation"]["address"]["addressRegion"].as_s.should eq("MI")
      unrecognised_json.as_h.has_key?("jobLocation").should be_false
      blank_json.as_h.has_key?("jobLocation").should be_false
    end
  end

  describe "#to_html_safe_json" do
    it "neutralises characters that could close the surrounding script tag" do
      job = JobFactory.create &.title(%(</script><script>alert(1)</script>))
        .published_at(Time.utc).active(true)

      escaped = JobPostingSchema.new(job).to_html_safe_json

      escaped.should_not contain("</script>")
      escaped.should_not contain("<script>")

      # Still valid, faithful JSON once the escapes are decoded - the
      # defence is cosmetic to HTML and invisible to a real JSON consumer.
      JSON.parse(escaped)["title"].as_s.should eq(%(</script><script>alert(1)</script>))
    end

    it "leaves plain content and JSON syntax untouched" do
      job = JobFactory.create &.title("Ordinary Title").published_at(Time.utc).active(true)

      escaped = JobPostingSchema.new(job).to_html_safe_json

      JSON.parse(escaped)["title"].as_s.should eq("Ordinary Title")
    end
  end
end
