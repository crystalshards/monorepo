-- Create job_postings table
CREATE TABLE job_postings (
  id SERIAL PRIMARY KEY,
  title VARCHAR(255) NOT NULL,
  company VARCHAR(255) NOT NULL,
  location VARCHAR(255) NOT NULL,
  job_type VARCHAR(50) NOT NULL CHECK (job_type IN ('full-time', 'part-time', 'contract', 'freelance')),
  salary_range VARCHAR(100),
  description TEXT NOT NULL,
  requirements TEXT,
  application_email VARCHAR(255) NOT NULL,
  company_website VARCHAR(500),
  company_logo_url VARCHAR(500),
  featured BOOLEAN NOT NULL DEFAULT FALSE,
  approved BOOLEAN NOT NULL DEFAULT FALSE,
  expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
  views INTEGER NOT NULL DEFAULT 0,
  applications INTEGER NOT NULL DEFAULT 0,
  stripe_payment_id VARCHAR(255),
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

-- Create indexes
CREATE INDEX idx_job_postings_approved ON job_postings(approved);
CREATE INDEX idx_job_postings_featured ON job_postings(featured);
CREATE INDEX idx_job_postings_job_type ON job_postings(job_type);
CREATE INDEX idx_job_postings_expires_at ON job_postings(expires_at);
CREATE INDEX idx_job_postings_created_at ON job_postings(created_at DESC);
CREATE INDEX idx_job_postings_views ON job_postings(views DESC);

-- Full text search index
CREATE INDEX idx_job_postings_search ON job_postings USING GIN(to_tsvector('english', title || ' ' || company || ' ' || location || ' ' || description || ' ' || COALESCE(requirements, '')));

-- Create updated_at trigger
CREATE TRIGGER update_job_postings_updated_at BEFORE UPDATE ON job_postings FOR EACH ROW EXECUTE PROCEDURE update_updated_at_column();