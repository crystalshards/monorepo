-- Create shards table
CREATE TABLE shards (
  id SERIAL PRIMARY KEY,
  name VARCHAR(255) NOT NULL UNIQUE,
  description TEXT,
  github_url VARCHAR(500) NOT NULL,
  homepage_url VARCHAR(500),
  documentation_url VARCHAR(500),
  license VARCHAR(100),
  latest_version VARCHAR(50),
  download_count INTEGER NOT NULL DEFAULT 0,
  stars INTEGER NOT NULL DEFAULT 0,
  forks INTEGER NOT NULL DEFAULT 0,
  last_activity TIMESTAMP WITH TIME ZONE,
  tags TEXT[] DEFAULT '{}',
  crystal_versions TEXT[] DEFAULT '{}',
  dependencies JSONB DEFAULT '{}',
  published BOOLEAN NOT NULL DEFAULT FALSE,
  featured BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

-- Create indexes
CREATE INDEX idx_shards_name ON shards(name);
CREATE INDEX idx_shards_github_url ON shards(github_url);
CREATE INDEX idx_shards_published ON shards(published);
CREATE INDEX idx_shards_featured ON shards(featured);
CREATE INDEX idx_shards_download_count ON shards(download_count DESC);
CREATE INDEX idx_shards_stars ON shards(stars DESC);
CREATE INDEX idx_shards_last_activity ON shards(last_activity DESC);
CREATE INDEX idx_shards_tags ON shards USING GIN(tags);
CREATE INDEX idx_shards_dependencies ON shards USING GIN(dependencies);

-- Full text search index
CREATE INDEX idx_shards_search ON shards USING GIN(to_tsvector('english', name || ' ' || COALESCE(description, '')));

-- Create updated_at trigger
CREATE TRIGGER update_shards_updated_at BEFORE UPDATE ON shards FOR EACH ROW EXECUTE PROCEDURE update_updated_at_column();