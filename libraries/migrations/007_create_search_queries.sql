-- Create search_queries table for analytics
CREATE TABLE search_queries (
  id SERIAL PRIMARY KEY,
  query VARCHAR(500) NOT NULL,
  results_count INTEGER NOT NULL DEFAULT 0,
  user_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
  ip_address INET,
  user_agent TEXT,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

-- Create indexes
CREATE INDEX idx_search_queries_query ON search_queries(query);
CREATE INDEX idx_search_queries_user_id ON search_queries(user_id);
CREATE INDEX idx_search_queries_created_at ON search_queries(created_at DESC);
CREATE INDEX idx_search_queries_ip_address ON search_queries(ip_address);

-- Create updated_at trigger
CREATE TRIGGER update_search_queries_updated_at BEFORE UPDATE ON search_queries FOR EACH ROW EXECUTE PROCEDURE update_updated_at_column();