class Home::IndexPage < MainLayout
  needs featured_jobs : Array(Job)
  needs recent_jobs : Array(Job)
  needs total_jobs : Int64
  needs total_companies : Int64

  def page_title
    "Find Crystal Programming Jobs"
  end

  # The landing page of a job board exists to get someone to a role. Search
  # lives in the masthead, so the page itself leads with what the board is and
  # what you do next. There is no hero image; a decorative photograph pushed
  # the jobs a full screen further down.
  def content
    render_intro
    render_getting_started
    render_job_lists
    render_hiring_cta
  end

  private def render_intro
    section class: "intro" do
      div class: "intro-copy" do
        h1 class: "intro-title" do
          text "Crystal jobs, posted by the "
          span class: "accent" do
            text "people hiring"
          end
        end

        para class: "intro-lede" do
          text "The job board for the Crystal community: every role comes " \
               "straight from the company trying to fill it."
        end

        div class: "intro-cta" do
          a href: "/jobs/new", class: "button button-primary button-large" do
            text "Post a Job - #{Pricing.price_label}"
          end
        end
      end

      dl class: "intro-stats" do
        div do
          tag "dt" do
            text "Active jobs"
          end
          tag "dd" do
            text @total_jobs.to_s
          end
        end
        div do
          tag "dt" do
            text "Companies hiring"
          end
          tag "dd" do
            text @total_companies.to_s
          end
        end
      end
    end
  end

  # The three things you actually do on a job board, with the exact URL you
  # paste to do each.
  private def render_getting_started
    section class: "section" do
      h2 class: "visually-hidden" do
        text "Getting started"
      end

      div class: "recipe-grid" do
        recipe(
          "Browse roles",
          "Every active posting, newest first.",
          "crystalgigs.com/jobs"
        )
        recipe(
          "Remote only",
          "Narrow the board to roles marked remote.",
          "crystalgigs.com/jobs?remote=true"
        )
        recipe(
          "Post a role",
          "#{Pricing.summary}, live as soon as payment clears.",
          "crystalgigs.com/jobs/new"
        )
      end
    end
  end

  private def recipe(title : String, blurb : String, snippet : String)
    article class: "recipe" do
      h3 do
        text title
      end
      para do
        text blurb
      end
      div class: "code-block" do
        pre do
          code do
            text snippet
          end
        end
      end
    end
  end

  private def render_job_lists
    if @featured_jobs.any?
      section class: "section" do
        div class: "section-header" do
          h2 do
            text "Featured Jobs"
          end
          para class: "section-subtitle" do
            text "Hand-picked opportunities from top companies"
          end
        end

        div class: "job-grid" do
          @featured_jobs.each do |job|
            mount JobCard, job: job, featured: true, heading_level: 3
          end
        end
      end
    end

    if @recent_jobs.any?
      section class: "section" do
        div class: "section-header" do
          h2 do
            text "Recent Job Postings"
          end
        end

        div class: "job-grid" do
          @recent_jobs.each do |job|
            mount JobCard, job: job, heading_level: 3
          end
        end

        div class: "section-footer" do
          a href: "/jobs", class: "view-all-link" do
            text "View All Jobs →"
          end
        end
      end
    end
  end

  private def render_hiring_cta
    section class: "section section-cta" do
      div class: "cta-box" do
        h2 do
          text "Looking to Hire Crystal Developers?"
        end
        para do
          text "Reach thousands of talented Crystal developers with a job posting on CrystalGigs"
        end
        a href: "/jobs/new", class: "button button-primary button-large" do
          text "Post a Job Now"
        end
      end
    end
  end
end
