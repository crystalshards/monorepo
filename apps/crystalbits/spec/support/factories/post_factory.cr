class PostFactory < Avram::Factory
  def initialize
    # Use a unique slug with timestamp and random component to avoid conflicts
    timestamp = Time.utc.to_unix_ms
    random = Random.rand(1000000)
    title "Building Web Applications with Crystal #{timestamp}-#{random}"
    slug "building-web-applications-with-crystal-#{timestamp}-#{random}"
    content "Crystal is an amazing language for building web applications..."
    excerpt "Crystal is an amazing language for building web applications..."
    author_name "Crystal Developer"
    author_email "dev@crystalbits.example.com"
    tags ["crystal", "web", "tutorial"]
    published_at Time.utc
    featured false
    view_count 0
  end
end
