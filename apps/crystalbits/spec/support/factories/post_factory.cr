class PostFactory < Avram::Factory
  def initialize
    title "Building Web Applications with Crystal"
    slug "building-web-applications-with-crystal"
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
