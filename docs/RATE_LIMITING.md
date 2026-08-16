# Rate Limiting Guide

## Overview

CrystalShards platform actions declare rate limits with Lucky's built-in `Lucky::RateLimit` module, which counts requests in the configured `LuckyCache` store.

## Rate Limits by Endpoint

### CrystalShards (crystalshards.org)

| Endpoint | Method | Rate Limit | Window |
|----------|--------|------------|--------|
| `/api/shards` | POST | 10 requests | 1 hour |
| `/api/shards/:name/:version/download` | POST | 100 requests | 1 hour |
| All other endpoints | GET | No limit | - |

### CrystalGigs (crystalgigs.com)

| Endpoint | Method | Rate Limit | Window |
|----------|--------|------------|--------|
| `/api/jobs` | POST | 5 requests | 1 hour |
| All other endpoints | GET | No limit | - |

### CrystalBits (crystalbits.org)

| Endpoint | Method | Rate Limit | Window |
|----------|--------|------------|--------|
| `/api/posts` | POST | 10 requests | 1 hour |
| `/api/newsletter/subscriptions` | POST | 10 requests per client address | 1 hour |
| All other endpoints | GET | No limit | - |

`/api/newsletter/subscriptions` is also bounded on a second axis, because an
open endpoint that sends mail is a spam relay if either axis is left open:

- Per subscribed address, `CrystalBits::Subscriptions::ATTEMPTS_PER_ADDRESS`
  attempts per `ATTEMPTS_PER_ADDRESS_WINDOW` (5 per hour). Excess attempts
  get the same redirect a successful subscribe gets, with no further effect.
- Per subscribed address, at most one confirmation email per
  `CrystalBits::Subscriptions::CONFIRMATION_RESEND_INTERVAL` (1 hour).
  Re-submitting an unconfirmed address re-sends the confirmation, never in a
  stream.

The response never reveals whether an address is new, already subscribed, or
already confirmed: every non-junk submission redirects to the same
confirmation_sent page.

### CrystalDocs (crystaldocs.org)

| Endpoint | Method | Rate Limit | Window |
|----------|--------|------------|--------|
| All endpoints | GET | No limit | - |

## How Rate Limiting Works

### Identification

Rate limits are tracked per IP address by default. The system uses the client's IP address from `context.request.remote_ip` to identify unique users.

### Response Headers

When a rate limit is exceeded, the API returns:

```http
HTTP/1.1 429 Too Many Requests
Retry-After: 3600
Content-Type: text/plain

Rate limit exceeded
```

The `Retry-After` header indicates how many seconds until the rate limit resets.

### Rate Limit Storage

Counters live in the configured `LuckyCache` store, keyed as:

```
ratelimit:<action_class>:<identifier>
```

For example:

```
ratelimit:api:shards:create:192.168.1.100
ratelimit:api:jobs:create:10.0.0.50
```

## Adding Rate Limiting to Actions

To add rate limiting to a Lucky action, include the `Lucky::RateLimit` module and define the rate limit:

```crystal
class Api::Shards::Create < ApiAction
  include Lucky::RateLimit
  rate_limit to: 10, within: 1.hour

  post "/api/shards" do
    # Your action code here
  end
end
```

### Custom Rate Limit Identifiers

By default, rate limiting uses IP addresses. You can customize the identifier by overriding the `rate_limit_identifier` method:

```crystal
class Api::Shards::Create < ApiAction
  include Lucky::RateLimit
  rate_limit to: 10, within: 1.hour

  # Use authenticated user ID instead of IP
  private def rate_limit_identifier : String
    current_user?.try(&.id.to_s) || super
  end

  post "/api/shards" do
    # Your action code here
  end
end
```

### Per-User Rate Limiting

For authenticated endpoints, you might want to apply rate limits per user rather than per IP:

```crystal
class Api::Shards::Create < ApiAction
  include Lucky::RateLimit
  rate_limit to: 50, within: 1.day

  private def rate_limit_identifier : String
    # Rate limit by API key or user ID
    current_user.api_key
  end

  post "/api/shards" do
    # Your action code here
  end
end
```

## Configuration

`Lucky::RateLimit` reads and writes `LuckyCache.settings.storage`. That
setting defaults to `LuckyCache::NullStore`, which discards writes and reads
back nothing. CrystalBits configures `LuckyCache::MemoryStore` in
`config/cache.cr`, so its limits are enforced per process; the other apps
still run the NullStore, so their declared limits never accumulate.

A memory store is per process and per instance. That is enough for what these
limits protect against: casual abuse and bursts. An attacker with many
instances' worth of traffic to spread across still meets the per-address
floors on the newsletter endpoint, which are the properties that actually
make it safe.

## Best Practices

### For API Users

1. **Handle 429 responses gracefully**: Implement exponential backoff when rate limits are hit
2. **Cache responses**: Reduce the number of API calls by caching responses locally
3. **Use webhooks**: For real-time updates, use webhooks instead of polling
4. **Monitor your usage**: Track your API usage to avoid hitting rate limits

### For API Developers

1. **Set appropriate limits**: Balance between preventing abuse and allowing legitimate use
2. **Document limits clearly**: Include rate limits in API documentation
3. **Monitor abuse patterns**: Track rate limit violations to detect malicious behavior
4. **Consider different tiers**: For public APIs, consider offering higher limits for paid plans
5. **Use sliding windows**: Lucky's rate limiting uses sliding windows, which is more fair than fixed windows

## Troubleshooting

### Rate Limits Not Working

1. **Check the cache store**: `LuckyCache.settings.storage` must retain values. The default `NullStore` drops every counter, so nothing accumulates. CrystalBits configures `LuckyCache::MemoryStore` in `config/cache.cr`; the other apps have no override yet
2. **Test locally**: Use `curl` or `httpie` to test rate limiting manually

### False Positives (Legitimate Users Being Limited)

1. **Proxy/NAT issues**: Users behind the same proxy/NAT share an IP address
   - Solution: Use authenticated user IDs for rate limiting instead of IPs
2. **Limits too strict**: Adjust the `to` and `within` parameters
3. **Shared hosting**: Multiple users on the same hosting provider may share IPs
   - Solution: Whitelist known hosting provider IPs or use API keys

### Performance Issues

1. **Key expiration**: Rate limit counters are written with the window as their expiry, so they clear themselves

## Future Enhancements

Potential improvements to rate limiting:

1. **Tiered rate limits**: Different limits for free vs. paid users
2. **Per-endpoint custom messages**: More descriptive rate limit messages
3. **Rate limit headers**: Include `X-RateLimit-Limit`, `X-RateLimit-Remaining`, `X-RateLimit-Reset` headers
4. **Distributed rate limiting**: Better support for multi-region deployments
5. **Dynamic rate limits**: Adjust limits based on system load or user behavior

## Resources

- [Lucky Framework Rate Limiting Docs](https://luckyframework.org/guides/http-and-routing/rate-limiting)
- [HTTP 429 Status Code](https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/429)
