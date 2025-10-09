class Home::IndexPage < MainLayout
  needs featured_jobs : Array(Job)
  needs recent_jobs : Array(Job)
  needs total_jobs : Int64
  needs total_companies : Int64

  def page_title
    "Find Crystal Programming Jobs"
  end

  def content
    section class: "hero" do
      div class: "hero-content" do
        h1 class: "hero-title" do
          text "Find Your Next Crystal Job"
        end

        para class: "hero-subtitle" do
          text "The premier job board for Crystal developers and companies hiring Crystal talent"
        end

        mount SearchBar, query: nil, large: true

        div class: "hero-stats" do
          div class: "stat" do
            strong do
              text @total_jobs.to_s
            end
            text " active jobs"
          end
          div class: "stat" do
            strong do
              text @total_companies.to_s
            end
            text " companies hiring"
          end
        end

        div class: "hero-cta" do
          a href: "/jobs/new", class: "button button-primary button-large" do
            text "Post a Job - $99"
          end
        end
      end
    end

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
            mount JobCard, job: job, featured: true
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
            mount JobCard, job: job
          end
        end

        div class: "section-footer" do
          a href: "/jobs", class: "view-all-link" do
            text "View All Jobs →"
          end
        end
      end
    end

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
