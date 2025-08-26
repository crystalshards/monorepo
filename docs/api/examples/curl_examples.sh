#!/bin/bash

# CrystalShards Platform API - cURL Examples
# 
# This script demonstrates how to interact with the CrystalShards Platform API
# using cURL commands. Each section shows different API endpoints and features.

set -e

# Configuration
API_BASE_URL="https://api.crystalshards.org"
DOCS_API_URL="https://docs-api.crystalshards.org"
GIGS_API_URL="https://gigs-api.crystalshards.org"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 CrystalShards Platform API - cURL Examples${NC}\n"

# Function to make pretty JSON output
pretty_json() {
    if command -v jq &> /dev/null; then
        jq '.'
    else
        cat
    fi
}

# Function to show section header
section() {
    echo -e "\n${YELLOW}=== $1 ===${NC}"
}

# ===== CRYSTALSHARDS REGISTRY API =====

section "API Information"
echo "GET $API_BASE_URL/api/v1"
curl -s "$API_BASE_URL/api/v1" | pretty_json
echo

section "Health Check"
echo "GET $API_BASE_URL/health"
curl -s "$API_BASE_URL/health" | pretty_json
echo

section "List Shards (with pagination)"
echo "GET $API_BASE_URL/api/v1/shards?page=1&per_page=3"
curl -s "$API_BASE_URL/api/v1/shards?page=1&per_page=3" | pretty_json
echo

section "Get Specific Shard"
echo "GET $API_BASE_URL/api/v1/shards/kemal"
curl -s "$API_BASE_URL/api/v1/shards/kemal" | pretty_json
echo

section "Basic Search"
echo "GET $API_BASE_URL/api/v1/search?q=web+framework"
curl -s "$API_BASE_URL/api/v1/search?q=web+framework" | pretty_json
echo

section "Advanced Search with Filters"
echo "GET $API_BASE_URL/api/v1/search?q=http&sort_by=stars&min_stars=50&license=MIT&highlight=true"
curl -s "$API_BASE_URL/api/v1/search?q=http&sort_by=stars&min_stars=50&license=MIT&highlight=true" | pretty_json
echo

section "Search Suggestions (Autocomplete)"
echo "GET $API_BASE_URL/api/v1/search/suggestions?q=kem&limit=5"
curl -s "$API_BASE_URL/api/v1/search/suggestions?q=kem&limit=5" | pretty_json
echo

section "Available Search Filters"
echo "GET $API_BASE_URL/api/v1/search/filters"
curl -s "$API_BASE_URL/api/v1/search/filters" | pretty_json
echo

section "Trending Searches"
echo "GET $API_BASE_URL/api/v1/search/trending?limit=5"
curl -s "$API_BASE_URL/api/v1/search/trending?limit=5" | pretty_json
echo

section "Popular Searches"
echo "GET $API_BASE_URL/api/v1/search/popular?limit=5"
curl -s "$API_BASE_URL/api/v1/search/popular?limit=5" | pretty_json
echo

section "Search Analytics"
echo "GET $API_BASE_URL/api/v1/search/analytics?days=7"
curl -s "$API_BASE_URL/api/v1/search/analytics?days=7" | pretty_json
echo

# ===== AUTHENTICATED ENDPOINTS =====

if [ -n "$CRYSTALSHARDS_API_KEY" ]; then
    section "Submit Shard (Authenticated)"
    echo "POST $API_BASE_URL/api/v1/shards"
    echo "Authorization: Bearer \$CRYSTALSHARDS_API_KEY"
    echo "Content-Type: application/json"
    echo "Body: {\"github_url\": \"https://github.com/example/repo\"}"
    echo
    echo -e "${GREEN}Example command:${NC}"
    echo 'curl -X POST "$API_BASE_URL/api/v1/shards" \'
    echo '  -H "Authorization: Bearer $CRYSTALSHARDS_API_KEY" \'
    echo '  -H "Content-Type: application/json" \'
    echo '  -d "{\"github_url\": \"https://github.com/user/awesome-shard\"}"'
    echo
else
    section "Submit Shard (Requires Authentication)"
    echo -e "${YELLOW}Set CRYSTALSHARDS_API_KEY environment variable to test authenticated endpoints${NC}"
    echo
    echo "export CRYSTALSHARDS_API_KEY=\"your-api-key-here\""
    echo 'curl -X POST "$API_BASE_URL/api/v1/shards" \'
    echo '  -H "Authorization: Bearer $CRYSTALSHARDS_API_KEY" \'
    echo '  -H "Content-Type: application/json" \'
    echo '  -d "{\"github_url\": \"https://github.com/user/awesome-shard\"}"'
    echo
fi

# ===== CRYSTALDOCS PLATFORM API =====

section "Documentation Build Request (Requires Auth)"
echo "POST $DOCS_API_URL/docs/api/v1/build"
echo "Content-Type: application/json"
echo
echo -e "${GREEN}Example command:${NC}"
echo 'curl -X POST "$DOCS_API_URL/docs/api/v1/build" \'
echo '  -H "Authorization: Bearer $CRYSTALSHARDS_API_KEY" \'
echo '  -H "Content-Type: application/json" \'
echo '  -d "{'
echo '    \"shard_name\": \"kemal\",'
echo '    \"version\": \"1.4.0\",'
echo '    \"github_url\": \"https://github.com/kemalcr/kemal\"'
echo '  }"'
echo

section "Documentation Search"
echo "GET $DOCS_API_URL/docs/api/v1/search?q=HTTP+client&shard=crest"
echo
echo -e "${GREEN}Example command:${NC}"
echo 'curl -s "$DOCS_API_URL/docs/api/v1/search?q=HTTP+client&shard=crest&per_page=3" | jq .'
echo

section "Get Documentation Content"
echo "GET $DOCS_API_URL/docs/kemal/1.4.0"
echo
echo -e "${GREEN}Example command:${NC}"
echo 'curl -s "$DOCS_API_URL/docs/kemal/1.4.0" \'
echo '  -H "Accept: application/json"'
echo

# ===== CRYSTALGIGS JOB BOARD API =====

section "List Job Postings"
echo "GET $GIGS_API_URL/jobs/api/v1/jobs?job_type=full_time&per_page=3"
echo
echo -e "${GREEN}Example command:${NC}"
echo 'curl -s "$GIGS_API_URL/jobs/api/v1/jobs?job_type=full_time&per_page=3" | jq .'
echo

section "Search Jobs"
echo "GET $GIGS_API_URL/jobs/api/v1/jobs?search=backend+developer&location=remote"
echo
echo -e "${GREEN}Example command:${NC}"
echo 'curl -s "$GIGS_API_URL/jobs/api/v1/jobs?search=backend+developer&location=remote" | jq .'
echo

section "Create Job Posting (with Stripe Payment)"
echo "POST $GIGS_API_URL/jobs/api/v1/jobs"
echo "Content-Type: application/json"
echo
echo -e "${GREEN}Example command:${NC}"
echo 'curl -X POST "$GIGS_API_URL/jobs/api/v1/jobs" \'
echo '  -H "Content-Type: application/json" \'
echo '  -d "{'
echo '    \"title\": \"Senior Crystal Developer\",'
echo '    \"company\": \"Tech Corp\",'
echo '    \"description\": \"We are looking for an experienced Crystal developer...\",'
echo '    \"job_type\": \"full_time\",'
echo '    \"location\": \"San Francisco, CA\",'
echo '    \"salary_range\": \"$120,000 - $180,000\",'
echo '    \"contact_email\": \"hiring@techcorp.com\",'
echo '    \"tags\": [\"backend\", \"api\", \"microservices\"]'
echo '  }"'
echo

# ===== MONITORING AND METRICS =====

section "Prometheus Metrics"
echo "GET $API_BASE_URL/metrics"
echo "GET $DOCS_API_URL/metrics"
echo "GET $GIGS_API_URL/metrics"
echo
echo -e "${GREEN}Example commands:${NC}"
echo 'curl -s "$API_BASE_URL/metrics" | grep crystalshards_'
echo 'curl -s "$DOCS_API_URL/metrics" | grep crystaldocs_'
echo 'curl -s "$GIGS_API_URL/metrics" | grep crystalgigs_'
echo

# ===== WEBHOOK EXAMPLES =====

section "GitHub Webhook (Repository Updates)"
echo "POST $API_BASE_URL/webhooks/github"
echo "X-Hub-Signature-256: sha256=..."
echo "Content-Type: application/json"
echo
echo -e "${GREEN}Example webhook payload:${NC}"
echo 'curl -X POST "$API_BASE_URL/webhooks/github" \'
echo '  -H "X-Hub-Signature-256: sha256=computed-signature" \'
echo '  -H "Content-Type: application/json" \'
echo '  -d "{'
echo '    \"action\": \"published\",'
echo '    \"repository\": {'
echo '      \"html_url\": \"https://github.com/user/repo\"'
echo '    }'
echo '  }"'
echo

section "Stripe Webhook (Payment Events)"
echo "POST $GIGS_API_URL/webhooks/stripe"
echo "Stripe-Signature: t=...,v1=..."
echo "Content-Type: application/json"
echo
echo -e "${GREEN}Note: Stripe webhooks are automatically configured in your Stripe dashboard${NC}"
echo

# ===== RATE LIMITING EXAMPLES =====

section "Rate Limiting Headers"
echo -e "${YELLOW}All API responses include rate limiting headers:${NC}"
echo "X-RateLimit-Limit: 100        # Total requests allowed per hour"
echo "X-RateLimit-Remaining: 87     # Requests remaining in window"
echo "X-RateLimit-Reset: 1640995200 # Unix timestamp when limit resets"
echo

echo -e "${GREEN}Example with rate limit headers:${NC}"
echo 'curl -I "$API_BASE_URL/api/v1" | grep X-RateLimit'
echo

# ===== ERROR HANDLING =====

section "Error Handling Examples"
echo -e "${RED}404 Not Found:${NC}"
echo 'curl -s "$API_BASE_URL/api/v1/shards/nonexistent" | jq .'
echo

echo -e "${RED}400 Bad Request:${NC}"
echo 'curl -s "$API_BASE_URL/api/v1/search?sort_by=invalid" | jq .'
echo

echo -e "${RED}401 Unauthorized:${NC}"
echo 'curl -X POST "$API_BASE_URL/api/v1/shards" \'
echo '  -H "Content-Type: application/json" \'
echo '  -d "{\"github_url\": \"https://github.com/user/repo\"}" | jq .'
echo

# ===== PERFORMANCE TESTING =====

section "Performance Testing"
echo -e "${YELLOW}Test API performance with curl timing:${NC}"
echo 'curl -w "Total time: %{time_total}s\nDNS lookup: %{time_namelookup}s\nConnect: %{time_connect}s\nTTFB: %{time_starttransfer}s\n" \'
echo '  -s -o /dev/null "$API_BASE_URL/api/v1/search?q=web"'
echo

echo -e "${YELLOW}Load testing with curl (simple):${NC}"
echo 'for i in {1..10}; do'
echo '  time curl -s "$API_BASE_URL/health" > /dev/null'
echo 'done'
echo

echo -e "\n${GREEN}✨ cURL Examples Complete!${NC}"
echo
echo -e "${BLUE}💡 Tips:${NC}"
echo "- Install jq for pretty JSON formatting: sudo apt install jq"
echo "- Use -v flag with curl for verbose output and debugging"
echo "- Set CRYSTALSHARDS_API_KEY for authenticated endpoints"
echo "- Check response headers for rate limiting information"
echo "- Use -w flag for performance timing information"
echo
echo -e "${BLUE}🔗 Resources:${NC}"
echo "- Interactive API Docs: https://docs.crystalshards.org/api/"
echo "- OpenAPI Spec: https://docs.crystalshards.org/api/openapi.yml"
echo "- GitHub Repository: https://github.com/crystalshards/monorepo"