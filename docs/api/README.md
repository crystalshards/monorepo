# CrystalShards Platform API Documentation

Welcome to the comprehensive API documentation for the CrystalShards ecosystem! This documentation covers three integrated platforms:

## 🏗️ Platforms

### 1. **CrystalShards Registry** - `api.crystalshards.org`
The central package registry for Crystal language shards (similar to rubygems.org or npmjs.com).

**Key Features:**
- Submit and discover Crystal shards
- Advanced search with filtering and sorting
- Real-time analytics and trending searches
- GitHub integration and webhooks
- Rate limiting and authentication

### 2. **CrystalDocs Platform** - `docs-api.crystalshards.org`
Automated documentation generation and hosting platform (similar to docs.rs).

**Key Features:**
- Sandboxed documentation builds
- Version-specific documentation hosting
- Full-text search across all documentation
- Build status monitoring and logs
- Cross-linking and reference navigation

### 3. **CrystalGigs Job Board** - `gigs-api.crystalshards.org`
Premium job board for Crystal developers with integrated payments.

**Key Features:**
- Paid job postings with Stripe integration
- Advanced job search and filtering
- Automated payment processing
- Job expiration and management
- Employer verification

## 🚀 Quick Start

### 1. **View Interactive Documentation**
```bash
# Serve the documentation locally
cd docs/api
python -m http.server 8080
# Open http://localhost:8080 in your browser
```

### 2. **Download OpenAPI Specification**
```bash
# Download the complete OpenAPI 3.0 specification
curl -O https://raw.githubusercontent.com/crystalshards/monorepo/main/docs/api/openapi.yml
```

### 3. **Generate Client SDKs**
```bash
# Generate client libraries using OpenAPI Generator
npx @openapitools/openapi-generator-cli generate \
  -i docs/api/openapi.yml \
  -g crystal \
  -o clients/crystal

# Or generate for other languages
npx @openapitools/openapi-generator-cli generate \
  -i docs/api/openapi.yml \
  -g typescript-axios \
  -o clients/typescript
```

## 🔐 Authentication

### JWT Authentication
```bash
# Login to get JWT token (when user authentication is implemented)
curl -X POST https://api.crystalshards.org/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email": "user@example.com", "password": "password"}'

# Use JWT token in requests
curl -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  https://api.crystalshards.org/api/v1/shards
```

### API Key Authentication
```bash
# Use API key (when available)
curl -H "Authorization: Bearer YOUR_API_KEY" \
  https://api.crystalshards.org/api/v1/shards
```

## 📚 Example Usage

### Search Shards
```bash
# Basic search
curl "https://api.crystalshards.org/api/v1/search?q=web+framework"

# Advanced search with filters
curl "https://api.crystalshards.org/api/v1/search?q=http&sort_by=stars&min_stars=100&license=MIT&highlight=true"

# Get search suggestions
curl "https://api.crystalshards.org/api/v1/search/suggestions?q=kem&limit=5"
```

### Submit a Shard
```bash
# Submit a shard (requires authentication)
curl -X POST https://api.crystalshards.org/api/v1/shards \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"github_url": "https://github.com/user/awesome-shard"}'
```

### Trigger Documentation Build
```bash
# Start documentation build
curl -X POST https://docs-api.crystalshards.org/docs/api/v1/build \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "shard_name": "kemal",
    "version": "1.4.0",
    "github_url": "https://github.com/kemalcr/kemal"
  }'

# Check build status
curl https://docs-api.crystalshards.org/docs/api/v1/build/build_123abc/status
```

### Post a Job
```bash
# Create job posting with payment
curl -X POST https://gigs-api.crystalshards.org/jobs/api/v1/jobs \
  -H "Content-Type: application/json" \
  -d '{
    "title": "Senior Crystal Developer",
    "company": "Tech Corp",
    "description": "We are looking for an experienced Crystal developer...",
    "job_type": "full_time",
    "location": "San Francisco, CA",
    "salary_range": "$120,000 - $180,000",
    "contact_email": "hiring@techcorp.com"
  }'
```

## 📊 Rate Limits

| Authentication | Requests/Hour | Burst Limit |
|----------------|---------------|-------------|
| Anonymous      | 100           | 10/min      |
| JWT User       | 2,000         | 60/min      |
| API Key (Basic)| 1,000         | 30/min      |
| API Key (Pro)  | 10,000        | 120/min     |

Rate limit headers are included in all responses:
- `X-RateLimit-Limit`: Total requests allowed per hour
- `X-RateLimit-Remaining`: Requests remaining in current window
- `X-RateLimit-Reset`: Unix timestamp when limit resets

## 🛠️ Development

### Local Development Setup
```bash
# Start all services with Docker Compose
make dev

# Or start individual services
cd apps/shards-registry && crystal run src/crystalshards.cr
cd apps/shards-docs && crystal run src/crystaldocs.cr
cd apps/gigs && crystal run src/crystalgigs.cr
```

### Testing API Endpoints
```bash
# Health checks
curl http://localhost:3000/health
curl http://localhost:3001/health
curl http://localhost:3002/health

# Prometheus metrics
curl http://localhost:3000/metrics
```

## 🔧 Error Handling

All API endpoints return consistent error responses:

```json
{
  "error": "Error type",
  "message": "Detailed error description"
}
```

Common HTTP status codes:
- `200` - Success
- `201` - Created (for POST requests)
- `400` - Bad Request (invalid parameters)
- `401` - Unauthorized (authentication required)
- `403` - Forbidden (insufficient permissions)
- `404` - Not Found
- `409` - Conflict (duplicate resource)
- `422` - Unprocessable Entity (validation errors)
- `429` - Too Many Requests (rate limited)
- `500` - Internal Server Error

## 📈 Monitoring

### Prometheus Metrics
All services expose Prometheus metrics at `/metrics`:

```
# HTTP request metrics
crystalshards_http_requests_total{method="GET",status="200"} 1234
crystalshards_http_request_duration_seconds_bucket{le="0.1"} 856

# Business metrics
crystalshards_search_duration_seconds_sum 45.2
crystalshards_shard_submissions_total 156
crystalgigs_payments_completed_total 23
```

### Health Monitoring
```bash
# Check service health
curl https://api.crystalshards.org/health
curl https://docs-api.crystalshards.org/health
curl https://gigs-api.crystalshards.org/health
```

## 🤝 Contributing

1. **Report Issues**: Found a bug or have a feature request? [Create an issue](https://github.com/crystalshards/monorepo/issues)

2. **Improve Documentation**: Submit PRs to improve API documentation

3. **Add Examples**: Contribute more usage examples and client libraries

4. **Test Endpoints**: Help test the API and report any issues

## 📞 Support

- **Documentation**: [docs.crystalshards.org](https://docs.crystalshards.org)
- **Issues**: [GitHub Issues](https://github.com/crystalshards/monorepo/issues)
- **Email**: [support@crystalshards.org](mailto:support@crystalshards.org)
- **Community**: [Crystal Language Forum](https://forum.crystal-lang.org)

## 📄 License

This API documentation and the CrystalShards platform are licensed under the MIT License.

---

**Built with ❤️ for the Crystal community**