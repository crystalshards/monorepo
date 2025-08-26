-- Create documentation table
CREATE TABLE documentation (
  id SERIAL PRIMARY KEY,
  shard_id INTEGER NOT NULL REFERENCES shards(id) ON DELETE CASCADE,
  version VARCHAR(50) NOT NULL,
  content_path VARCHAR(500) NOT NULL,
  build_status VARCHAR(20) NOT NULL DEFAULT 'pending' CHECK (build_status IN ('pending', 'building', 'success', 'failed')),
  build_log TEXT,
  file_count INTEGER NOT NULL DEFAULT 0,
  size_bytes BIGINT NOT NULL DEFAULT 0,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  UNIQUE(shard_id, version)
);

-- Create indexes
CREATE INDEX idx_documentation_shard_id ON documentation(shard_id);
CREATE INDEX idx_documentation_version ON documentation(version);
CREATE INDEX idx_documentation_build_status ON documentation(build_status);
CREATE INDEX idx_documentation_created_at ON documentation(created_at DESC);

-- Create updated_at trigger
CREATE TRIGGER update_documentation_updated_at BEFORE UPDATE ON documentation FOR EACH ROW EXECUTE PROCEDURE update_updated_at_column();