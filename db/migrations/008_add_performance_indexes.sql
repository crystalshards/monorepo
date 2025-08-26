-- Performance optimization indexes for CrystalShards platform
-- These indexes significantly improve search query performance

-- Add full-text search indexes for shards table
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_shards_search_tsvector 
ON shards USING gin(to_tsvector('english', name || ' ' || COALESCE(description, '')));

-- Add partial index for published shards only (most common query)
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_shards_published_search
ON shards (published, stars DESC, updated_at DESC) 
WHERE published = TRUE;

-- Add index for stars ranking (affects search result ordering)
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_shards_stars_desc
ON shards (stars DESC, created_at DESC) 
WHERE published = TRUE;

-- Add index for GitHub URL lookups (used during shard submission)
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_shards_github_url
ON shards (github_url);

-- Add full-text search indexes for job_postings table
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_jobs_search_tsvector
ON job_postings USING gin(to_tsvector('english', title || ' ' || company || ' ' || location || ' ' || description));

-- Add composite index for active job searches
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_jobs_active_search
ON job_postings (approved, expires_at, featured DESC, created_at DESC)
WHERE approved = TRUE AND expires_at > NOW();

-- Add index for job location searches
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_jobs_location
ON job_postings (location) 
WHERE approved = TRUE AND expires_at > NOW();

-- Add index for company searches
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_jobs_company
ON job_postings (company)
WHERE approved = TRUE AND expires_at > NOW();

-- Add index for documentation table searches
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_documentation_shard_version
ON documentation (shard_id, version, build_status);

-- Add index for documentation content path lookups
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_documentation_content_path
ON documentation (content_path) 
WHERE build_status = 'completed';

-- Add indexes for frequently accessed counts
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_shards_published_count
ON shards (published) WHERE published = TRUE;

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_jobs_approved_count  
ON job_postings (approved) WHERE approved = TRUE;

-- Update table statistics for query planner
ANALYZE shards;
ANALYZE job_postings; 
ANALYZE documentation;

-- Add comments for documentation
COMMENT ON INDEX idx_shards_search_tsvector IS 'Full-text search index for shard names and descriptions';
COMMENT ON INDEX idx_shards_published_search IS 'Composite index for published shards with ranking';
COMMENT ON INDEX idx_jobs_search_tsvector IS 'Full-text search index for job postings';
COMMENT ON INDEX idx_jobs_active_search IS 'Composite index for active job searches with sorting';