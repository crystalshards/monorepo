#!/usr/bin/env python3
"""
CrystalShards API Client Example (Python)

This example demonstrates how to interact with the CrystalShards Platform API
using Python's requests library.

Install dependencies:
    pip install requests

Usage:
    python python_client.py --example
"""

import requests
from typing import Optional, Dict, List, Any
import json
from urllib.parse import urlencode


class CrystalShardsClient:
    """Python client for CrystalShards Platform API"""
    
    def __init__(self, base_url: str = "https://api.crystalshards.org", api_key: Optional[str] = None):
        self.base_url = base_url.rstrip('/')
        self.api_key = api_key
        self.session = requests.Session()
        
        # Set default headers
        self.session.headers.update({
            'Content-Type': 'application/json',
            'User-Agent': 'CrystalShardsClient/1.0.0 (Python)'
        })
        
        if self.api_key:
            self.session.headers['Authorization'] = f'Bearer {self.api_key}'
    
    def _request(self, method: str, endpoint: str, **kwargs) -> Dict[str, Any]:
        """Make HTTP request with error handling"""
        url = f"{self.base_url}{endpoint}"
        
        try:
            response = self.session.request(method, url, **kwargs)
            response.raise_for_status()
            return response.json()
        except requests.exceptions.HTTPError as e:
            error_data = {}
            try:
                error_data = response.json()
            except:
                pass
            
            error_msg = error_data.get('error') or error_data.get('message') or str(e)
            raise Exception(f"API Error {response.status_code}: {error_msg}")
        except requests.exceptions.RequestException as e:
            raise Exception(f"Request failed: {str(e)}")
    
    def search_shards(self, query: str, **options) -> Dict[str, Any]:
        """Search for Crystal shards"""
        params = {'q': query}
        params.update({k: v for k, v in options.items() if v is not None})
        
        return self._request('GET', f'/api/v1/search?{urlencode(params)}')
    
    def get_shard(self, name: str) -> Optional[Dict[str, Any]]:
        """Get details for a specific shard"""
        try:
            return self._request('GET', f'/api/v1/shards/{name}')
        except Exception as e:
            if '404' in str(e):
                return None
            raise
    
    def submit_shard(self, github_url: str) -> Dict[str, Any]:
        """Submit a new shard (requires authentication)"""
        if not self.api_key:
            raise Exception("API key required for shard submission")
        
        payload = {'github_url': github_url}
        return self._request('POST', '/api/v1/shards', json=payload)
    
    def get_suggestions(self, query: str, limit: int = 10) -> Dict[str, Any]:
        """Get search suggestions (autocomplete)"""
        params = {'q': query, 'limit': limit}
        return self._request('GET', f'/api/v1/search/suggestions?{urlencode(params)}')
    
    def get_trending_searches(self, limit: int = 20) -> Dict[str, Any]:
        """Get trending searches"""
        params = {'limit': limit}
        return self._request('GET', f'/api/v1/search/trending?{urlencode(params)}')
    
    def get_popular_searches(self, limit: int = 20) -> Dict[str, Any]:
        """Get popular searches"""
        params = {'limit': limit}
        return self._request('GET', f'/api/v1/search/popular?{urlencode(params)}')
    
    def get_search_analytics(self, days: int = 7) -> Dict[str, Any]:
        """Get search analytics"""
        params = {'days': days}
        return self._request('GET', f'/api/v1/search/analytics?{urlencode(params)}')
    
    def get_search_filters(self) -> Dict[str, Any]:
        """Get available search filters"""
        return self._request('GET', '/api/v1/search/filters')
    
    def list_shards(self, page: int = 1, per_page: int = 20) -> Dict[str, Any]:
        """Get list of shards with pagination"""
        params = {'page': page, 'per_page': per_page}
        return self._request('GET', f'/api/v1/shards?{urlencode(params)}')
    
    def get_api_info(self) -> Dict[str, Any]:
        """Get API information"""
        return self._request('GET', '/api/v1')
    
    def health_check(self) -> Dict[str, Any]:
        """Health check"""
        return self._request('GET', '/health')


def example():
    """Example usage of the CrystalShards API client"""
    print("🚀 CrystalShards API Client Example\n")
    
    # Create client instance
    client = CrystalShardsClient()
    
    try:
        # Get API information
        print("=== API Info ===")
        api_info = client.get_api_info()
        print(f"API: {api_info.get('message')}")
        print(f"Version: {api_info.get('version')}")
        print()
        
        # Health check
        print("=== Health Check ===")
        health = client.health_check()
        print(f"Status: {health.get('status')}")
        print(f"Timestamp: {health.get('timestamp')}")
        print()
        
        # Search for shards
        print("=== Search Results ===")
        search_results = client.search_shards(
            query="web framework",
            sort_by="stars",
            per_page=5,
            highlight=True
        )
        
        print(f'Query: "{search_results.get("query")}"')
        print(f"Total: {search_results.get('total')}")
        print("Results:")
        
        for i, shard in enumerate(search_results.get('results', []), 1):
            print(f"  {i}. {shard.get('name')} - {shard.get('description')}")
            print(f"     ⭐ {shard.get('stars')} stars | 📦 {shard.get('downloads')} downloads")
        print()
        
        # Get specific shard
        print("=== Shard Details ===")
        shard = client.get_shard('kemal')
        if shard:
            print(f"Name: {shard.get('name')}")
            print(f"Description: {shard.get('description')}")
            print(f"GitHub: {shard.get('github_url')}")
            print(f"License: {shard.get('license')}")
            print(f"Stars: {shard.get('stars')}")
            print(f"Tags: {', '.join(shard.get('tags', []))}")
        else:
            print("Shard 'kemal' not found")
        print()
        
        # Get search suggestions
        print("=== Search Suggestions ===")
        suggestions = client.get_suggestions('kem', 5)
        print("Suggestions for 'kem':")
        for suggestion in suggestions.get('suggestions', []):
            print(f"  - {suggestion}")
        print()
        
        # Get trending searches
        print("=== Trending Searches ===")
        trending = client.get_trending_searches(5)
        print(f"Trending searches ({trending.get('period')}):")
        for i, search in enumerate(trending.get('trending_searches', []), 1):
            query = search.get('query')
            count = search.get('count')
            growth_rate = search.get('growth_rate')
            print(f"  {i}. \"{query}\" - {count} searches ({growth_rate}% growth)")
        print()
        
        # Get search filters
        print("=== Available Filters ===")
        filters = client.get_search_filters()
        print(f"Licenses: {', '.join(filters.get('licenses', []))}")
        print(f"Crystal Versions: {', '.join(filters.get('crystal_versions', []))}")
        tags = filters.get('tags', [])
        print(f"Tags: {', '.join(tags[:10])}{'...' if len(tags) > 10 else ''}")
        print()
        
        print("✨ Example completed successfully!")
        print("\n💡 To submit a shard, set your API key:")
        print("   client = CrystalShardsClient(api_key='your-api-key')")
        print("   client.submit_shard('https://github.com/user/repo')")
        
    except Exception as e:
        print(f"❌ Error: {e}")


class CrystalShardsAsync:
    """Async version using aiohttp (optional)"""
    
    def __init__(self, base_url: str = "https://api.crystalshards.org", api_key: Optional[str] = None):
        self.base_url = base_url.rstrip('/')
        self.api_key = api_key
    
    async def _request(self, method: str, endpoint: str, **kwargs):
        """Make async HTTP request"""
        try:
            import aiohttp
        except ImportError:
            raise Exception("aiohttp required for async client: pip install aiohttp")
        
        headers = {
            'Content-Type': 'application/json',
            'User-Agent': 'CrystalShardsClient/1.0.0 (Python/Async)'
        }
        
        if self.api_key:
            headers['Authorization'] = f'Bearer {self.api_key}'
        
        url = f"{self.base_url}{endpoint}"
        
        async with aiohttp.ClientSession(headers=headers) as session:
            async with session.request(method, url, **kwargs) as response:
                if not response.ok:
                    error_data = {}
                    try:
                        error_data = await response.json()
                    except:
                        pass
                    
                    error_msg = error_data.get('error') or error_data.get('message') or f"HTTP {response.status}"
                    raise Exception(f"API Error {response.status}: {error_msg}")
                
                return await response.json()
    
    async def search_shards(self, query: str, **options) -> Dict[str, Any]:
        """Async search for shards"""
        params = {'q': query}
        params.update({k: v for k, v in options.items() if v is not None})
        
        return await self._request('GET', f'/api/v1/search?{urlencode(params)}')


if __name__ == "__main__":
    import sys
    
    if "--example" in sys.argv:
        example()
    else:
        print(__doc__)
        print("\nUsage: python python_client.py --example")