/**
 * CrystalShards API Client Example (JavaScript/TypeScript)
 * 
 * This example demonstrates how to interact with the CrystalShards Platform API
 * using JavaScript (works in Node.js and browsers with fetch API support).
 */

class CrystalShardsClient {
  constructor(baseUrl = 'https://api.crystalshards.org', apiKey = null) {
    this.baseUrl = baseUrl;
    this.apiKey = apiKey;
  }

  /**
   * Make authenticated HTTP request
   */
  async request(endpoint, options = {}) {
    const url = `${this.baseUrl}${endpoint}`;
    const headers = {
      'Content-Type': 'application/json',
      'User-Agent': 'CrystalShardsClient/1.0.0',
      ...options.headers
    };

    if (this.apiKey) {
      headers['Authorization'] = `Bearer ${this.apiKey}`;
    }

    const response = await fetch(url, {
      ...options,
      headers
    });

    if (!response.ok) {
      const errorData = await response.json().catch(() => ({ error: 'Unknown error' }));
      throw new Error(`API Error ${response.status}: ${errorData.error || errorData.message || 'Unknown error'}`);
    }

    return response.json();
  }

  /**
   * Search for Crystal shards
   */
  async searchShards(query, options = {}) {
    const params = new URLSearchParams({
      q: query,
      ...Object.fromEntries(
        Object.entries(options).filter(([_, value]) => value !== null && value !== undefined)
      )
    });

    return this.request(`/api/v1/search?${params}`);
  }

  /**
   * Get details for a specific shard
   */
  async getShard(name) {
    try {
      return await this.request(`/api/v1/shards/${encodeURIComponent(name)}`);
    } catch (error) {
      if (error.message.includes('404')) {
        return null; // Shard not found
      }
      throw error;
    }
  }

  /**
   * Submit a new shard (requires authentication)
   */
  async submitShard(githubUrl) {
    if (!this.apiKey) {
      throw new Error('API key required for shard submission');
    }

    return this.request('/api/v1/shards', {
      method: 'POST',
      body: JSON.stringify({ github_url: githubUrl })
    });
  }

  /**
   * Get search suggestions (autocomplete)
   */
  async getSuggestions(query, limit = 10) {
    const params = new URLSearchParams({
      q: query,
      limit: limit.toString()
    });

    return this.request(`/api/v1/search/suggestions?${params}`);
  }

  /**
   * Get trending searches
   */
  async getTrendingSearches(limit = 20) {
    const params = new URLSearchParams({
      limit: limit.toString()
    });

    return this.request(`/api/v1/search/trending?${params}`);
  }

  /**
   * Get popular searches
   */
  async getPopularSearches(limit = 20) {
    const params = new URLSearchParams({
      limit: limit.toString()
    });

    return this.request(`/api/v1/search/popular?${params}`);
  }

  /**
   * Get search analytics
   */
  async getSearchAnalytics(days = 7) {
    const params = new URLSearchParams({
      days: days.toString()
    });

    return this.request(`/api/v1/search/analytics?${params}`);
  }

  /**
   * Get available search filters
   */
  async getSearchFilters() {
    return this.request('/api/v1/search/filters');
  }

  /**
   * Get list of shards with pagination
   */
  async listShards(page = 1, perPage = 20) {
    const params = new URLSearchParams({
      page: page.toString(),
      per_page: perPage.toString()
    });

    return this.request(`/api/v1/shards?${params}`);
  }

  /**
   * Get API information
   */
  async getApiInfo() {
    return this.request('/api/v1');
  }

  /**
   * Health check
   */
  async healthCheck() {
    return this.request('/health');
  }
}

// Example usage (if running in Node.js)
async function example() {
  console.log('🚀 CrystalShards API Client Example\n');

  // Create client instance
  const client = new CrystalShardsClient();

  try {
    // Get API information
    console.log('=== API Info ===');
    const apiInfo = await client.getApiInfo();
    console.log(`API: ${apiInfo.message}`);
    console.log(`Version: ${apiInfo.version}`);
    console.log();

    // Health check
    console.log('=== Health Check ===');
    const health = await client.healthCheck();
    console.log(`Status: ${health.status}`);
    console.log(`Timestamp: ${health.timestamp}`);
    console.log();

    // Search for shards
    console.log('=== Search Results ===');
    const searchResults = await client.searchShards('web framework', {
      sort_by: 'stars',
      per_page: 5,
      highlight: true
    });

    console.log(`Query: "${searchResults.query}"`);
    console.log(`Total: ${searchResults.total}`);
    console.log('Results:');
    
    if (searchResults.results) {
      searchResults.results.forEach((shard, index) => {
        console.log(`  ${index + 1}. ${shard.name} - ${shard.description}`);
        console.log(`     ⭐ ${shard.stars} stars | 📦 ${shard.downloads} downloads`);
      });
    }
    console.log();

    // Get specific shard
    console.log('=== Shard Details ===');
    const shard = await client.getShard('kemal');
    if (shard) {
      console.log(`Name: ${shard.name}`);
      console.log(`Description: ${shard.description}`);
      console.log(`GitHub: ${shard.github_url}`);
      console.log(`License: ${shard.license}`);
      console.log(`Stars: ${shard.stars}`);
      console.log(`Tags: ${shard.tags?.join(', ')}`);
    } else {
      console.log("Shard 'kemal' not found");
    }
    console.log();

    // Get search suggestions
    console.log('=== Search Suggestions ===');
    const suggestions = await client.getSuggestions('kem', 5);
    console.log("Suggestions for 'kem':");
    if (suggestions.suggestions) {
      suggestions.suggestions.forEach(suggestion => {
        console.log(`  - ${suggestion}`);
      });
    }
    console.log();

    // Get trending searches
    console.log('=== Trending Searches ===');
    const trending = await client.getTrendingSearches(5);
    console.log(`Trending searches (${trending.period}):`);
    if (trending.trending_searches) {
      trending.trending_searches.forEach((search, index) => {
        const { query, count, growth_rate } = search;
        console.log(`  ${index + 1}. "${query}" - ${count} searches (${growth_rate}% growth)`);
      });
    }
    console.log();

    // Get search filters
    console.log('=== Available Filters ===');
    const filters = await client.getSearchFilters();
    console.log(`Licenses: ${filters.licenses?.join(', ')}`);
    console.log(`Crystal Versions: ${filters.crystal_versions?.join(', ')}`);
    console.log(`Tags: ${filters.tags?.slice(0, 10).join(', ')}${filters.tags?.length > 10 ? '...' : ''}`);
    console.log();

    console.log('✨ Example completed successfully!');
    console.log('\n💡 To submit a shard, set your API key:');
    console.log('   const client = new CrystalShardsClient("https://api.crystalshards.org", "your-api-key");');
    console.log('   await client.submitShard("https://github.com/user/repo");');

  } catch (error) {
    console.error('❌ Error:', error.message);
  }
}

// Enhanced TypeScript type definitions (optional)
if (typeof module !== 'undefined' && module.exports) {
  // Node.js environment
  if (!global.fetch) {
    console.log('💡 For Node.js < 18, install node-fetch: npm install node-fetch');
    console.log('   Then add: global.fetch = require("node-fetch");');
  }
  
  module.exports = { CrystalShardsClient, example };
  
  // Run example if this file is executed directly
  if (require.main === module) {
    example();
  }
} else {
  // Browser environment - make class globally available
  window.CrystalShardsClient = CrystalShardsClient;
}

// TypeScript type definitions (if using TypeScript)
/*
export interface SearchOptions {
  sort_by?: 'relevance' | 'stars' | 'downloads' | 'recent' | 'name';
  license?: string;
  crystal_version?: string;
  tags?: string;
  min_stars?: number;
  featured?: boolean;
  activity_days?: number;
  page?: number;
  per_page?: number;
  highlight?: boolean;
}

export interface Shard {
  id: number;
  name: string;
  description: string;
  github_url: string;
  license?: string;
  crystal_version?: string;
  tags?: string[];
  stars: number;
  forks: number;
  downloads: number;
  published: boolean;
  featured: boolean;
  created_at: string;
  updated_at: string;
  last_activity?: string;
}

export interface SearchResult {
  query: string;
  results: Shard[];
  total: number;
  page: number;
  per_page: number;
  pages: number;
  highlights_enabled: boolean;
}
*/