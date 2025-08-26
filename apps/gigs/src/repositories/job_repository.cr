require "pg"
require "json"
require "../../../libraries/shared/src/services/cache_service"

module CrystalGigs
  class JobRepository
    def self.create_job(job_data : Hash(String, String), stripe_payment_id : String? = nil)
      expires_at = Time.utc + 30.days
      
      query = <<-SQL
        INSERT INTO job_postings (
          title, company, location, job_type, salary_range, description,
          application_email, company_website, stripe_payment_id, expires_at,
          approved, featured
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
        RETURNING id, created_at
      SQL
      
      begin
        result = DB.query_one(query,
          job_data["title"],
          job_data["company"],
          job_data["location"],
          job_data["type"],
          job_data["salary"],
          job_data["description"],
          job_data["email"],
          job_data["website"],
          stripe_payment_id,
          expires_at,
          stripe_payment_id ? true : false, # approved if paid
          stripe_payment_id ? true : false  # featured if paid
        ) do |rs|
          {
            id: rs.read(Int32),
            created_at: rs.read(Time)
          }
        end
        
        # Invalidate search caches when new job is created
        CACHE.invalidate_search("jobs")
        CACHE.invalidate_pattern("stats:gigs")
        
        result
      rescue ex : Exception
        puts "Database error creating job: #{ex.message}"
        nil
      end
    end
    
    def self.update_payment_status(job_id : Int32, stripe_payment_id : String)
      query = <<-SQL
        UPDATE job_postings 
        SET stripe_payment_id = $2, approved = true, featured = true, updated_at = NOW()
        WHERE id = $1
        RETURNING id
      SQL
      
      begin
        DB.query_one(query, job_id, stripe_payment_id) do |rs|
          rs.read(Int32)
        end
      rescue ex : Exception
        puts "Error updating payment status: #{ex.message}"
        nil
      end
    end
    
    def self.get_job_by_id(id : Int32)
      query = <<-SQL
        SELECT id, title, company, location, job_type, salary_range, description,
               application_email, company_website, approved, featured, expires_at,
               views, applications, stripe_payment_id, created_at, updated_at
        FROM job_postings 
        WHERE id = $1
      SQL
      
      begin
        DB.query_one(query, id) do |rs|
          {
            id: rs.read(Int32),
            title: rs.read(String),
            company: rs.read(String),
            location: rs.read(String),
            job_type: rs.read(String),
            salary_range: rs.read(String?),
            description: rs.read(String),
            application_email: rs.read(String),
            company_website: rs.read(String?),
            approved: rs.read(Bool),
            featured: rs.read(Bool),
            expires_at: rs.read(Time),
            views: rs.read(Int32),
            applications: rs.read(Int32),
            stripe_payment_id: rs.read(String?),
            created_at: rs.read(Time),
            updated_at: rs.read(Time)
          }
        end
      rescue ex : Exception
        puts "Error getting job by ID: #{ex.message}"
        nil
      end
    end
    
    def self.get_all_jobs(approved_only : Bool = true, limit : Int32 = 20, offset : Int32 = 0)
      where_clause = approved_only ? "WHERE approved = true AND expires_at > NOW()" : "WHERE expires_at > NOW()"
      
      query = <<-SQL
        SELECT id, title, company, location, job_type, salary_range, description,
               application_email, company_website, approved, featured, expires_at,
               views, applications, created_at
        FROM job_postings 
        #{where_clause}
        ORDER BY featured DESC, created_at DESC
        LIMIT $1 OFFSET $2
      SQL
      
      begin
        jobs = [] of Hash(String, JSON::Any)
        DB.query(query, limit, offset) do |rs|
          rs.each do
            jobs << {
              "id" => JSON::Any.new(rs.read(Int32).to_i64),
              "title" => JSON::Any.new(rs.read(String)),
              "company" => JSON::Any.new(rs.read(String)),
              "location" => JSON::Any.new(rs.read(String)),
              "job_type" => JSON::Any.new(rs.read(String)),
              "salary_range" => JSON::Any.new(rs.read(String?)),
              "description" => JSON::Any.new(rs.read(String)),
              "application_email" => JSON::Any.new(rs.read(String)),
              "company_website" => JSON::Any.new(rs.read(String?)),
              "approved" => JSON::Any.new(rs.read(Bool)),
              "featured" => JSON::Any.new(rs.read(Bool)),
              "expires_at" => JSON::Any.new(rs.read(Time).to_s),
              "views" => JSON::Any.new(rs.read(Int32).to_i64),
              "applications" => JSON::Any.new(rs.read(Int32).to_i64),
              "created_at" => JSON::Any.new(rs.read(Time).to_s)
            }
          end
        end
        
        jobs
      rescue ex : Exception
        puts "Error getting jobs: #{ex.message}"
        [] of Hash(String, JSON::Any)
      end
    end
    
    def self.search_jobs(query : String, limit : Int32 = 20, offset : Int32 = 0)
      # Try to get cached results first
      cached_results = CACHE.get_search_results("jobs", query, limit, offset, Array(Hash(String, JSON::Any)))
      return cached_results if cached_results

      search_query = <<-SQL
        SELECT id, title, company, location, job_type, salary_range, description,
               application_email, company_website, approved, featured, expires_at,
               views, applications, created_at,
               ts_rank_cd(to_tsvector('english', title || ' ' || company || ' ' || location || ' ' || description), 
                          plainto_tsquery('english', $1)) as rank
        FROM job_postings 
        WHERE approved = true 
        AND expires_at > NOW()
        AND to_tsvector('english', title || ' ' || company || ' ' || location || ' ' || description) 
            @@ plainto_tsquery('english', $1)
        ORDER BY rank DESC, featured DESC, created_at DESC
        LIMIT $2 OFFSET $3
      SQL
      
      begin
        jobs = [] of Hash(String, JSON::Any)
        DB.query(search_query, query, limit, offset) do |rs|
          rs.each do
            jobs << {
              "id" => JSON::Any.new(rs.read(Int32).to_i64),
              "title" => JSON::Any.new(rs.read(String)),
              "company" => JSON::Any.new(rs.read(String)),
              "location" => JSON::Any.new(rs.read(String)),
              "job_type" => JSON::Any.new(rs.read(String)),
              "salary_range" => JSON::Any.new(rs.read(String?)),
              "description" => JSON::Any.new(rs.read(String)),
              "application_email" => JSON::Any.new(rs.read(String)),
              "company_website" => JSON::Any.new(rs.read(String?)),
              "approved" => JSON::Any.new(rs.read(Bool)),
              "featured" => JSON::Any.new(rs.read(Bool)),
              "expires_at" => JSON::Any.new(rs.read(Time).to_s),
              "views" => JSON::Any.new(rs.read(Int32).to_i64),
              "applications" => JSON::Any.new(rs.read(Int32).to_i64),
              "created_at" => JSON::Any.new(rs.read(Time).to_s),
              "relevance" => JSON::Any.new(rs.read(Float64))
            }
          end
        end
        
        # Cache the results for 5 minutes 
        CACHE.cache_search_results("jobs", query, limit, offset, jobs, CacheService::TTL_SHORT)
        
        jobs
      rescue ex : Exception
        puts "Error searching jobs: #{ex.message}"
        [] of Hash(String, JSON::Any)
      end
    end
    
    def self.increment_views(job_id : Int32)
      query = "UPDATE job_postings SET views = views + 1 WHERE id = $1"
      
      begin
        DB.exec(query, job_id)
        true
      rescue ex : Exception
        puts "Error incrementing views: #{ex.message}"
        false
      end
    end
  end
end