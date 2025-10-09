class Db::Seed::SampleData < LuckyTask::Task
  summary "Add sample database records helpful for development"

  def call
    seed_job_postings
    puts "Done adding sample data"
  end

  private def seed_job_postings
    puts "Seeding job postings..."

    create_job(
      title: "Senior Crystal Backend Engineer",
      description: "Join our team building high-performance microservices in Crystal. We're looking for an experienced backend engineer who loves type-safe languages and wants to push the boundaries of what's possible with Crystal.\n\nResponsibilities:\n- Design and implement scalable API services\n- Optimize database queries and caching strategies\n- Mentor junior developers\n- Contribute to open source Crystal projects\n\nRequirements:\n- 5+ years backend development experience\n- Strong understanding of Crystal or similar compiled languages (Rust, Go)\n- Experience with PostgreSQL and Redis\n- Knowledge of microservices architecture",
      company_name: "TechCorp",
      company_url: "https://techcorp.example.com",
      location: "San Francisco, CA",
      remote: true,
      job_type: "full-time",
      salary_min: 150000,
      salary_max: 200000,
      apply_url: "https://techcorp.example.com/careers/crystal-backend-engineer",
      tags: ["crystal", "backend", "microservices", "postgresql", "redis"],
      published_at: 2.days.ago,
      expires_at: 60.days.from_now
    )

    create_job(
      title: "Crystal Developer - Remote",
      description: "We're building the next generation of cloud infrastructure tools using Crystal. Looking for passionate developers who want to work on developer tooling that impacts millions of users.\n\nWhat you'll do:\n- Build CLI tools and SDKs in Crystal\n- Improve build and deployment pipelines\n- Work with cloud APIs (AWS, GCP, Azure)\n- Write comprehensive tests and documentation\n\nQualifications:\n- 3+ years programming experience\n- Familiarity with Crystal, Ruby, or similar languages\n- Experience with cloud platforms\n- Strong communication skills",
      company_name: "CloudFlow",
      company_url: "https://cloudflow.dev",
      remote: true,
      job_type: "full-time",
      salary_min: 120000,
      salary_max: 160000,
      apply_url: "https://cloudflow.dev/jobs/crystal-developer",
      apply_email: "jobs@cloudflow.dev",
      tags: ["crystal", "devtools", "cloud", "remote"],
      published_at: 1.week.ago,
      expires_at: 45.days.from_now,
      featured: true
    )

    create_job(
      title: "Full Stack Developer (Crystal + React)",
      description: "Startup building a modern web application platform using Crystal on the backend and React on the frontend. Join our small team and have a huge impact.\n\nStack:\n- Backend: Crystal with Lucky framework\n- Frontend: React, TypeScript, TailwindCSS\n- Database: PostgreSQL\n- Infrastructure: Kubernetes, Docker\n\nWe're looking for:\n- Full stack experience (3+ years)\n- Comfortable with Crystal or willing to learn quickly\n- React expertise\n- Startup mindset and adaptability",
      company_name: "AppForge",
      company_url: "https://appforge.io",
      location: "Austin, TX",
      remote: true,
      job_type: "full-time",
      salary_min: 110000,
      salary_max: 145000,
      apply_url: "https://appforge.io/careers",
      tags: ["crystal", "react", "fullstack", "lucky", "startup"],
      published_at: 3.days.ago,
      expires_at: 30.days.from_now
    )

    create_job(
      title: "Junior Crystal Developer",
      description: "Perfect for developers early in their career who want to learn Crystal. We provide mentorship and pair programming to help you grow.\n\nYou'll learn:\n- Crystal language and ecosystem\n- Web development with Lucky framework\n- Database design and optimization\n- Testing and CI/CD practices\n\nRequirements:\n- 1+ year programming experience in any language\n- Basic understanding of web development\n- Eagerness to learn and grow\n- Computer Science degree or equivalent experience",
      company_name: "DevAcademy",
      location: "New York, NY",
      remote: false,
      job_type: "full-time",
      salary_min: 70000,
      salary_max: 90000,
      apply_email: "hiring@devacademy.com",
      tags: ["crystal", "junior", "mentorship", "lucky"],
      published_at: 5.days.ago,
      expires_at: 45.days.from_now
    )

    create_job(
      title: "Freelance Crystal Consultant",
      description: "Looking for experienced Crystal developers to consult on various client projects. Flexible hours and project-based work.\n\nProjects include:\n- API development and integration\n- Performance optimization\n- Code reviews and architecture consulting\n- Team training and mentorship\n\nIdeal candidate:\n- 5+ years Crystal experience\n- Strong communication skills\n- Available 10-20 hours per week\n- Experience across multiple domains",
      company_name: "CrystalConsulting",
      company_url: "https://crystalconsulting.dev",
      remote: true,
      job_type: "freelance",
      salary_min: 100,
      salary_max: 200,
      salary_currency: "USD",
      apply_url: "https://crystalconsulting.dev/apply",
      tags: ["crystal", "consulting", "freelance", "flexible"],
      published_at: 1.day.ago,
      expires_at: 90.days.from_now
    )

    create_job(
      title: "Crystal Platform Engineer",
      description: "Build and maintain internal developer platform tools using Crystal. Help shape the developer experience for hundreds of engineers.\n\nResponsibilities:\n- Develop internal CLI tools and libraries\n- Maintain CI/CD pipelines\n- Create developer documentation\n- Support engineering teams\n\nRequirements:\n- 4+ years platform/DevOps experience\n- Crystal or Go programming skills\n- Kubernetes and Docker expertise\n- Strong scripting abilities",
      company_name: "MegaCorp",
      location: "Seattle, WA",
      remote: true,
      job_type: "full-time",
      salary_min: 140000,
      salary_max: 180000,
      apply_url: "https://megacorp.com/careers/platform-engineer",
      tags: ["crystal", "platform", "devops", "kubernetes"],
      published_at: 2.weeks.ago,
      expires_at: 30.days.from_now
    )
  end

  private def create_job(title : String, description : String, company_name : String,
                         job_type : String, apply_url : String? = nil, apply_email : String? = nil,
                         company_url : String? = nil, location : String? = nil, remote : Bool = false,
                         salary_min : Int32? = nil, salary_max : Int32? = nil,
                         salary_currency : String = "USD", tags : Array(String) = [] of String,
                         published_at : Time? = nil, expires_at : Time? = nil, featured : Bool = false)
    return if JobQuery.new.title(title).company_name(company_name).any?

    SaveJob.create!(
      title: title,
      description: description,
      company_name: company_name,
      company_url: company_url,
      location: location,
      remote: remote,
      job_type: job_type,
      salary_min: salary_min,
      salary_max: salary_max,
      salary_currency: salary_currency,
      apply_url: apply_url,
      apply_email: apply_email,
      tags: tags,
      published_at: published_at || Time.utc,
      expires_at: expires_at,
      featured: featured,
      active: true
    )

    puts "  Created job: #{title} at #{company_name}"
  end
end
