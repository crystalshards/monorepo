class Db::Seed::SampleData < LuckyTask::Task
  summary "Add sample database records helpful for development"

  def call
    seed_blog_posts
    puts "Done adding sample data"
  end

  private def seed_blog_posts
    puts "Seeding blog posts..."

    create_post(
      title: "Crystal 1.0: A New Era for the Language",
      content: "After years of development and refinement, Crystal has finally reached version 1.0. This milestone represents not just a version number, but a commitment to stability and production-readiness.\n\nThe Crystal language combines the elegance of Ruby with the performance of compiled languages like C and Rust. With version 1.0, the core language features are now stable, and the API is guaranteed to remain backwards compatible.\n\nKey highlights of Crystal 1.0:\n\n- Stable Language Specification: No more breaking changes to core syntax\n- Mature Standard Library: Well-tested and documented\n- Production-Ready Performance: Benchmarks show Crystal competing with Go and Rust\n- Growing Ecosystem: Over 1000 shards available\n- Better Tooling: Improved compiler errors and debugging support\n\nThe community has been working hard to bring Crystal to this point, and the future looks bright. Whether you're building web applications, CLI tools, or systems software, Crystal 1.0 is ready for production use.\n\nWelcome to the future of Crystal programming!",
      author_name: "Jane Developer",
      author_email: "jane@crystalshards.org",
      tags: ["crystal", "release", "1.0", "milestone"],
      published_at: 1.week.ago,
      featured: true,
      view_count: 1500
    )

    create_post(
      title: "Building High-Performance APIs with Lucky Framework",
      content: "Lucky is a full-featured web framework for Crystal that emphasizes type safety and developer productivity. In this post, we'll explore how to build blazingly fast APIs with Lucky.\n\nWhy Lucky for APIs?\n\n1. Type Safety: Catch bugs at compile time, not runtime\n2. Performance: Crystal's compiled nature means sub-millisecond response times\n3. Developer Experience: Helpful error messages and intuitive patterns\n4. Built-in Tools: Authentication, validation, and database queries included\n\nGetting Started:\n\nFirst, create a new Lucky project:\n```\nlucky init.api my_api\ncd my_api\nshards install\n```\n\nCreate your first action:\n```crystal\nclass Api::Users::Index < ApiAction\n  get \"/api/users\" do\n    users = UserQuery.new.results\n    json UserSerializer.for_collection(users)\n  end\nend\n```\n\nThe type system ensures that your serializers match your models, and the query builder prevents SQL injection and N+1 queries.\n\nLucky makes it easy to build APIs that are both fast and maintainable. Give it a try!",
      author_name: "Alex Coder",
      author_email: "alex@example.com",
      tags: ["lucky", "api", "webdev", "tutorial"],
      published_at: 2.weeks.ago,
      view_count: 850
    )

    create_post(
      title: "Crystal vs Go vs Rust: Performance Comparison",
      content: "We ran extensive benchmarks comparing Crystal, Go, and Rust across various workloads. The results might surprise you.\n\nTest Setup:\n- HTTP server handling JSON payloads\n- Database queries (PostgreSQL)\n- CPU-intensive number crunching\n- Memory allocation patterns\n\nResults Summary:\n\nHTTP Performance:\n- Rust: 98,000 req/s\n- Crystal: 95,000 req/s\n- Go: 88,000 req/s\n\nDatabase Operations:\n- Crystal: 15,200 queries/s\n- Rust: 14,800 queries/s\n- Go: 13,500 queries/s\n\nCPU Workload:\n- Rust: 1.2s\n- Crystal: 1.3s\n- Go: 2.1s\n\nMemory Usage:\n- Go: 45 MB\n- Crystal: 52 MB\n- Rust: 48 MB\n\nConclusions:\n\nCrystal performs remarkably well, often matching or exceeding Rust's performance while maintaining Ruby-like syntax. Go trades some raw performance for simplicity and excellent concurrency primitives.\n\nThe choice between these languages depends on your priorities:\n- Choose Rust for maximum control and safety\n- Choose Crystal for performance + developer happiness\n- Choose Go for simplicity and excellent tooling\n\nAll three are excellent choices for modern backend development!",
      author_name: "Dr. Performance",
      author_email: "perf@example.com",
      tags: ["crystal", "go", "rust", "benchmarks", "performance"],
      published_at: 3.days.ago,
      featured: true,
      view_count: 2100
    )

    create_post(
      title: "Migrating from Ruby to Crystal: A Case Study",
      content: "Our team recently migrated a critical microservice from Ruby to Crystal. Here's what we learned.\n\nBackground:\nWe had a Ruby service processing millions of webhook events daily. Response times were acceptable but required significant infrastructure costs.\n\nThe Migration Process:\n\nWeek 1: Learning Crystal syntax and patterns\nWeek 2: Porting core business logic\nWeek 3: Database integration and testing\nWeek 4: Performance tuning and deployment\n\nChallenges:\n- No direct equivalent for some Ruby gems\n- Learning to think with types\n- Adjusting to compilation step\n\nBenefits:\n- 10x reduction in response time (200ms → 20ms)\n- 5x reduction in memory usage\n- 70% cost savings on infrastructure\n- Caught bugs at compile time\n\nThe Ruby-like syntax made the transition smooth for our team. Within a month, everyone was productive in Crystal.\n\nWould we do it again? Absolutely. Crystal gave us Ruby's developer experience with C's performance.",
      author_name: "Sarah Architect",
      author_email: "sarah@company.com",
      tags: ["crystal", "ruby", "migration", "case-study"],
      published_at: 10.days.ago,
      view_count: 1200
    )

    create_post(
      title: "Top 10 Crystal Shards You Should Know About",
      content: "The Crystal ecosystem is growing rapidly. Here are 10 essential shards every Crystal developer should know.\n\n1. Lucky - Full-featured web framework\n2. Kemal - Lightweight web framework\n3. Amber - Rails-like framework\n4. Granite/Jennifer - ORM solutions\n5. Spectator - Advanced testing framework\n6. Ameba - Code quality and linting\n7. Crystal-redis - Redis client\n8. Crystal-pg - PostgreSQL driver\n9. JWT - JSON Web Token support\n10. Crest - HTTP client\n\nEach of these shards solves real problems and has active maintenance. The Crystal community has done an excellent job building essential tools.\n\nWeb Frameworks:\nLucky, Kemal, and Amber each serve different needs. Lucky for type-safe full-stack apps, Kemal for microservices, and Amber for Rails refugees.\n\nDatabase:\nBoth Granite and Jennifer provide excellent ORM capabilities. Crystal-pg gives you raw PostgreSQL access when you need it.\n\nTesting:\nSpectator brings RSpec-style testing to Crystal with excellent documentation.\n\nThe ecosystem is mature enough for production use. Start building!",
      author_name: "Mike Curator",
      author_email: "mike@crystalbits.org",
      tags: ["crystal", "shards", "ecosystem", "libraries"],
      published_at: 5.days.ago,
      featured: true,
      view_count: 980
    )

    create_post(
      title: "Understanding Crystal's Type System",
      content: "Crystal's type system is one of its most powerful features. Let's explore how it works and why it matters.\n\nType Inference:\nCrystal automatically figures out types without explicit annotations:\n\n```crystal\nname = \"Crystal\"  # String\ncount = 42        # Int32\nratio = 3.14      # Float64\n```\n\nNilable Types:\nCrystal forces you to handle nil cases:\n\n```crystal\nuser = User.find?(id)\nif user\n  # user is User here\n  puts user.name\nelse\n  # user is Nil here\n  puts \"Not found\"\nend\n```\n\nUnion Types:\nVariables can hold multiple types:\n\n```crystal\nresult : String | Int32 = some_method\ncase result\nwhen String\n  puts result.upcase\nwhen Int32\n  puts result * 2\nend\n```\n\nGenerics:\nCreate reusable, type-safe code:\n\n```crystal\nclass Container(T)\n  def initialize(@value : T)\n  end\n  \n  def get : T\n    @value\n  end\nend\n```\n\nThe type system eliminates entire classes of bugs. Embrace it and your code will be more reliable.",
      author_name: "Prof. Types",
      author_email: "types@university.edu",
      tags: ["crystal", "types", "tutorial", "advanced"],
      published_at: 1.month.ago,
      view_count: 650
    )
  end

  private def create_post(title : String, content : String, author_name : String,
                          author_email : String? = nil, tags : Array(String) = [] of String,
                          published_at : Time? = nil, featured : Bool = false,
                          view_count : Int32 = 0)
    slug = title.downcase
      .gsub(/[^a-z0-9\s-]/, "")
      .gsub(/\s+/, "-")
      .gsub(/-+/, "-")
      .strip("-")

    return if PostQuery.new.slug(slug).any?

    excerpt = content[0...200] + (content.size > 200 ? "..." : "")

    SavePost.create!(
      title: title,
      slug: slug,
      content: content,
      excerpt: excerpt,
      author_name: author_name,
      author_email: author_email,
      tags: tags,
      published_at: published_at || Time.utc,
      featured: featured,
      view_count: view_count
    )

    puts "  Created post: #{title}"
  end
end
