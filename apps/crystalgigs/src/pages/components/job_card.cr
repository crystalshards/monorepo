class JobCard < Lucky::BaseComponent
  needs job : Job
  needs featured : Bool = false
  # Cards appear under an h2 on listings and homepage sections, so the level
  # is set by the caller rather than baked into the visual style.
  needs heading_level : Int32 = 3

  def render
    a href: "/jobs/#{@job.id}", class: card_class do
      div class: "job-card-header" do
        tag "h#{@heading_level}", class: "job-title" do
          text @job.title
        end

        if @featured
          span class: "badge badge-featured" do
            text "Featured"
          end
        end
      end

      div class: "job-company" do
        text @job.company_name
      end

      if description = truncate_description(@job.description)
        para class: "job-description" do
          text description
        end
      end

      div class: "job-meta" do
        if @job.remote
          span class: "badge badge-remote" do
            text "Remote"
          end
        end

        if location = @job.location
          span class: "job-location" do
            text location
          end
        end

        span class: "job-type" do
          text format_job_type(@job.job_type)
        end

        if salary_range = format_salary_range
          span class: "job-salary" do
            text salary_range
          end
        end
      end

      if @job.tags.any?
        div class: "job-tags" do
          @job.tags.each do |tag|
            span class: "tag" do
              text tag
            end
          end
        end
      end
    end
  end

  private def card_class
    classes = ["job-card"]
    classes << "job-card-featured" if @featured
    classes.join(" ")
  end

  private def truncate_description(text : String, max_length : Int32 = 150) : String
    return text if text.size <= max_length
    "#{text[0...max_length]}..."
  end

  private def format_job_type(type : String) : String
    type.split("-").map(&.capitalize).join(" ")
  end

  private def format_salary_range : String?
    min = @job.salary_min
    max = @job.salary_max
    currency = @job.salary_currency

    return nil if min.nil? && max.nil?

    if min && max
      "#{currency} #{format_number(min)} - #{format_number(max)}"
    elsif min
      "#{currency} #{format_number(min)}+"
    elsif max
      "Up to #{currency} #{format_number(max)}"
    end
  end

  private def format_number(num : Int32) : String
    num.to_s.reverse.gsub(/(\d{3})(?=\d)/, "\\1,").reverse
  end
end
