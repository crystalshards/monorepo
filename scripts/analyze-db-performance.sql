-- Database Performance Analysis Script for CrystalShards Platform
-- Run this script to analyze query performance and identify bottlenecks

-- Show current database statistics
SELECT 
    schemaname,
    tablename,
    n_tup_ins as inserts,
    n_tup_upd as updates,
    n_tup_del as deletes,
    n_live_tup as live_rows,
    n_dead_tup as dead_rows,
    last_vacuum,
    last_autovacuum,
    last_analyze,
    last_autoanalyze
FROM pg_stat_user_tables 
ORDER BY n_live_tup DESC;

-- Show index usage statistics  
SELECT
    schemaname,
    tablename,
    indexname,
    idx_tup_read,
    idx_tup_fetch,
    idx_scan as scans
FROM pg_stat_user_indexes
ORDER BY idx_scan DESC;

-- Identify unused indexes (potential for removal)
SELECT
    schemaname,
    tablename, 
    indexname,
    pg_size_pretty(pg_relation_size(indexname::regclass)) as size
FROM pg_stat_user_indexes
WHERE idx_scan = 0
ORDER BY pg_relation_size(indexname::regclass) DESC;

-- Show table sizes
SELECT
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as total_size,
    pg_size_pretty(pg_relation_size(schemaname||'.'||tablename)) as table_size,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename) - pg_relation_size(schemaname||'.'||tablename)) as index_size
FROM pg_tables 
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;

-- Show slow queries (requires pg_stat_statements extension)
-- Uncomment if pg_stat_statements is available:
/*
SELECT 
    query,
    calls,
    total_time,
    mean_time,
    rows,
    100.0 * shared_blks_hit / nullif(shared_blks_hit + shared_blks_read, 0) AS hit_percent
FROM pg_stat_statements 
WHERE query NOT LIKE '%pg_stat_statements%'
ORDER BY total_time DESC 
LIMIT 20;
*/

-- Show current connections and activity
SELECT 
    pid,
    usename,
    application_name,
    client_addr,
    state,
    query_start,
    state_change,
    left(query, 100) as current_query
FROM pg_stat_activity 
WHERE state != 'idle'
ORDER BY query_start;

-- Check for blocking queries
SELECT 
    blocked_locks.pid as blocked_pid,
    blocked_activity.usename as blocked_user,
    blocking_locks.pid as blocking_pid,
    blocking_activity.usename as blocking_user,
    blocked_activity.query as blocked_statement,
    blocking_activity.query as blocking_statement
FROM pg_catalog.pg_locks blocked_locks
JOIN pg_catalog.pg_stat_activity blocked_activity ON blocked_activity.pid = blocked_locks.pid
JOIN pg_catalog.pg_locks blocking_locks 
    ON blocking_locks.locktype = blocked_locks.locktype
    AND blocking_locks.DATABASE IS NOT DISTINCT FROM blocked_locks.DATABASE
    AND blocking_locks.relation IS NOT DISTINCT FROM blocked_locks.relation
    AND blocking_locks.page IS NOT DISTINCT FROM blocked_locks.page
    AND blocking_locks.tuple IS NOT DISTINCT FROM blocked_locks.tuple
    AND blocking_locks.virtualxid IS NOT DISTINCT FROM blocked_locks.virtualxid
    AND blocking_locks.transactionid IS NOT DISTINCT FROM blocked_locks.transactionid
    AND blocking_locks.classid IS NOT DISTINCT FROM blocked_locks.classid
    AND blocking_locks.objid IS NOT DISTINCT FROM blocked_locks.objid
    AND blocking_locks.objsubid IS NOT DISTINCT FROM blocked_locks.objsubid
    AND blocking_locks.pid != blocked_locks.pid
JOIN pg_catalog.pg_stat_activity blocking_activity ON blocking_activity.pid = blocking_locks.pid
WHERE NOT blocked_locks.GRANTED;

-- Analyze specific search query performance
EXPLAIN (ANALYZE, BUFFERS) 
SELECT id, name, description, stars, ts_rank(to_tsvector('english', name || ' ' || COALESCE(description, '')), plainto_tsquery('english', 'crystal')) as rank
FROM shards 
WHERE published = TRUE 
  AND (to_tsvector('english', name || ' ' || COALESCE(description, '')) @@ plainto_tsquery('english', 'crystal')
       OR name ILIKE '%crystal%')
ORDER BY rank DESC, stars DESC 
LIMIT 20;

-- Analyze job search query performance  
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, title, company, location, ts_rank_cd(to_tsvector('english', title || ' ' || company || ' ' || location || ' ' || description), plainto_tsquery('english', 'developer')) as rank
FROM job_postings 
WHERE approved = true 
  AND expires_at > NOW()
  AND to_tsvector('english', title || ' ' || company || ' ' || location || ' ' || description) @@ plainto_tsquery('english', 'developer')
ORDER BY rank DESC, featured DESC, created_at DESC
LIMIT 20;

-- Show cache hit ratios (should be > 95% for good performance)
SELECT 
    'cache_hit_ratio' as metric,
    sum(heap_blks_hit) / (sum(heap_blks_hit) + sum(heap_blks_read)) * 100 as percentage
FROM pg_statio_user_tables
UNION ALL
SELECT 
    'index_cache_hit_ratio' as metric,
    sum(idx_blks_hit) / (sum(idx_blks_hit) + sum(idx_blks_read)) * 100 as percentage  
FROM pg_statio_user_indexes;

-- Recommendations based on analysis
SELECT 'RECOMMENDATIONS' as analysis_type, 'Consider running VACUUM ANALYZE on tables with high dead_tup ratios' as recommendation
UNION ALL 
SELECT 'RECOMMENDATIONS', 'Monitor cache hit ratios - should be above 95%'
UNION ALL
SELECT 'RECOMMENDATIONS', 'Remove unused indexes to save space and improve write performance'
UNION ALL  
SELECT 'RECOMMENDATIONS', 'Consider partitioning large tables if they grow significantly'
UNION ALL
SELECT 'RECOMMENDATIONS', 'Enable pg_stat_statements for detailed query performance monitoring';