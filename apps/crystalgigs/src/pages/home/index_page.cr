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
        div do
          para class: "eyebrow" do
            text "The Crystal job board"
          end

          h1 class: "hero-title" do
            text "Find your next "
            span class: "accent" do
              text "Crystal job"
            end
            text "."
          end

          para class: "hero-subtitle" do
            text "The premier job board for Crystal developers and companies hiring Crystal talent"
          end

          mount SearchBar, query: nil, large: true, field_id: "hero-search"

          div class: "hero-cta" do
            a href: "/jobs/new", class: "button button-primary button-large" do
              text "Post a Job - $99"
            end
          end
        end

        tag "figure", class: "hero-figure" do
          img(
            src: asset("img/specimen-pyrite.webp"),
            srcset: "#{asset("img/specimen-pyrite.webp")} 560w, #{asset("img/specimen-pyrite@2x.webp")} 1120w",
            sizes: "(max-width: 60rem) 22rem, 33rem",
            width: "560", height: "560",
            alt: "A cubic pyrite specimen, brassy metallic cubes intergrown"
          )
          tag "figcaption" do
            text "Fig. 1 - Pyrite, cubic system"
          end
        end
      end

      div class: "hero-stats" do
        div class: "stat" do
          strong do
            text @total_jobs.to_s
          end
          span do
            text "Active jobs"
          end
        end
        div class: "stat" do
          strong do
            text @total_companies.to_s
          end
          span do
            text "Companies hiring"
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
