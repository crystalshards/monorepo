class Jobs::ShowPage < MainLayout
  needs job : Job

  def page_title
    "#{@job.title} at #{@job.company_name}"
  end

  def content
    article class: "job-detail" do
      div class: "job-detail-header" do
        div class: "job-detail-title-section" do
          h1 class: "job-detail-title" do
            text @job.title
          end

          div class: "job-detail-company" do
            if url = @job.company_url
              a href: url, target: "_blank", rel: "noopener" do
                text @job.company_name
              end
            else
              text @job.company_name
            end
          end
        end

        div class: "job-detail-meta" do
          if @job.featured
            span class: "badge badge-featured" do
              text "Featured"
            end
          end

          if @job.remote
            span class: "badge badge-remote" do
              text "Remote"
            end
          end

          if location = @job.location
            span class: "meta-item" do
              # The glyph is decorative; the location text carries the meaning.
              tag "i", class: "fa-solid fa-location-dot icon", "aria-hidden": "true"
              text location
            end
          end

          span class: "meta-item" do
            text format_job_type(@job.job_type)
          end

          if salary = format_salary_range
            span class: "meta-item" do
              tag "i", class: "fa-solid fa-sack-dollar icon", "aria-hidden": "true"
              text salary
            end
          end

          if published = @job.published_at
            span class: "meta-item meta-date" do
              text "Posted #{time_ago(published)}"
            end
          end
        end
      end

      div class: "job-detail-content" do
        section class: "job-section" do
          h2 do
            text "Job Description"
          end
          div class: "job-description-content" do
            render_markdown(@job.description)
          end
        end

        if @job.tags.any?
          section class: "job-section" do
            h2 do
              text "Skills & Technologies"
            end
            div class: "job-tags-list" do
              @job.tags.each do |tag|
                span class: "tag tag-large" do
                  text tag
                end
              end
            end
          end
        end

        section class: "job-section job-apply-section" do
          h2 do
            text "Apply for this Position"
          end

          div class: "apply-buttons" do
            if apply_url = @job.apply_url
              a href: apply_url, target: "_blank", rel: "noopener", class: "button button-primary button-large" do
                text "Apply Now"
              end
            end

            if email = @job.apply_email
              a href: "mailto:#{email}", class: "button button-secondary button-large" do
                text "Apply via Email"
              end
            end
          end
        end
      end

      aside class: "job-detail-sidebar" do
        div class: "sidebar-card" do
          h3 do
            text "About #{@job.company_name}"
          end

          if url = @job.company_url
            a href: url, target: "_blank", rel: "noopener", class: "company-website" do
              text "Visit Company Website →"
            end
          end
        end

        div class: "sidebar-card" do
          h3 do
            text "Share this Job"
          end
          div class: "share-buttons" do
            a href: "https://twitter.com/intent/tweet?text=#{URI.encode_www_form(@job.title)}&url=#{current_url}",
              target: "_blank",
              class: "share-button" do
              text "Share on Twitter"
            end
            a href: "https://www.linkedin.com/sharing/share-offsite/?url=#{current_url}",
              target: "_blank",
              class: "share-button" do
              text "Share on LinkedIn"
            end
          end
        end
      end
    end
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

  private def time_ago(time : Time) : String
    diff = Time.utc - time
    days = diff.days

    if days == 0
      "today"
    elsif days == 1
      "yesterday"
    elsif days < 7
      "#{days} days ago"
    elsif days < 30
      weeks = days // 7
      "#{weeks} week#{weeks > 1 ? "s" : ""} ago"
    else
      months = days // 30
      "#{months} month#{months > 1 ? "s" : ""} ago"
    end
  end

  # Job descriptions are written by whoever posts the job, so this is
  # untrusted input going into `raw`. It was passed through unescaped, which
  # made any description containing a script tag stored XSS on this origin.
  #
  # Escape first, then add the line breaks. The reverse order would escape the
  # breaks we just inserted, and escaping afterwards would be no protection at
  # all. This is the only markup the function has ever produced: it is a
  # newline-to-break conversion, not a Markdown renderer.
  private def render_markdown(text : String)
    raw HTML.escape(text).gsub("\n", "<br>")
  end

  private def current_url : String
    protocol = context.request.headers["X-Forwarded-Proto"]? || "http"
    host = context.request.headers["Host"]? || "localhost"
    "#{protocol}://#{host}#{context.request.path}"
  end
end
