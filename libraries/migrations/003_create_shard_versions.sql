-- Create shard_versions table
CREATE TABLE shard_versions (
  id SERIAL PRIMARY KEY,
  shard_id INTEGER NOT NULL REFERENCES shards(id) ON DELETE CASCADE,
  version VARCHAR(50) NOT NULL,
  commit_sha VARCHAR(40),
  release_notes TEXT,
  yanked BOOLEAN NOT NULL DEFAULT FALSE,
  prerelease BOOLEAN NOT NULL DEFAULT FALSE,
  documentation_generated BOOLEAN NOT NULL DEFAULT FALSE,
  download_count INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  UNIQUE(shard_id, version)
);

-- Create indexes
CREATE INDEX idx_shard_versions_shard_id ON shard_versions(shard_id);
CREATE INDEX idx_shard_versions_version ON shard_versions(version);
CREATE INDEX idx_shard_versions_yanked ON shard_versions(yanked);
CREATE INDEX idx_shard_versions_prerelease ON shard_versions(prerelease);
CREATE INDEX idx_shard_versions_download_count ON shard_versions(download_count DESC);
CREATE INDEX idx_shard_versions_created_at ON shard_versions(created_at DESC);

-- Create updated_at trigger
CREATE TRIGGER update_shard_versions_updated_at BEFORE UPDATE ON shard_versions FOR EACH ROW EXECUTE PROCEDURE update_updated_at_column();