# GitHub Webhook Setup Guide

## Overview

Configure GitHub to automatically notify CrystalShards.org when new shard versions are released. This enables automatic indexing of new versions without manual intervention.

## How It Works

1. You publish a new release on GitHub (or push a tag)
2. GitHub sends a webhook notification to CrystalShards.org
3. CrystalShards verifies the webhook signature for security
4. CrystalShards enqueues an indexing job for the new version
5. The shard version appears on CrystalShards.org within ~30 seconds

## Prerequisites

- Your shard must already be registered on CrystalShards.org
- You must have admin access to your GitHub repository
- You need the webhook secret from CrystalShards infrastructure

## Setup Steps

### 1. Get the Webhook Secret

The webhook secret is stored in the Kubernetes cluster. Infrastructure administrators can retrieve it:

```bash
kubectl get secret crystalshards-secrets -n crystalshards \
  -o jsonpath='{.data.github_webhook_secret}' | base64 -d
```

**Note:** Keep this secret secure. Do not commit it to version control.

### 2. Configure the Webhook on GitHub

1. Go to your shard repository on GitHub
2. Navigate to **Settings** → **Webhooks** → **Add webhook**
3. Configure the webhook:

   **Payload URL:**
   ```
   https://crystalshards.org/api/webhooks/github
   ```

   **Content type:**
   ```
   application/json
   ```

   **Secret:**
   ```
   [paste the webhook secret from step 1]
   ```

   **Which events would you like to trigger this webhook?**
   - ✅ **Releases** (recommended)
   - ✅ **Pushes** (optional, for tags without releases)

   **Active:**
   - ✅ Enabled

4. Click **Add webhook**

### 3. Test the Webhook

#### Option A: Create a New Release

1. Go to your repository's **Releases** page
2. Click **Draft a new release**
3. Create a tag (e.g., `v1.0.0`)
4. Add a release title and description
5. Click **Publish release**

#### Option B: Push a Tag

```bash
git tag v1.0.0
git push origin v1.0.0
```

### 4. Verify Webhook Delivery

1. Go to **Settings** → **Webhooks** on GitHub
2. Click on your webhook
3. Click **Recent Deliveries**
4. You should see a delivery with:
   - ✅ Green checkmark (200 response)
   - Response body: `{"status":"ok","message":"Webhook received"}`

### 5. Verify Shard Indexing

Check that your new version appears on CrystalShards.org:

```bash
curl https://crystalshards.org/api/shards/your-shard-name/versions/1.0.0
```

Or visit:
```
https://crystalshards.org/shards/your-shard-name
```

The new version should appear within 30 seconds.

## Troubleshooting

### Webhook Returns 401 Unauthorized

**Cause:** Invalid signature

**Solutions:**
- Verify you pasted the correct webhook secret
- Ensure there are no leading/trailing spaces in the secret
- Contact CrystalShards admins to verify the secret

### Webhook Returns 500 Internal Server Error

**Cause:** Server-side error

**Solutions:**
- Check CrystalShards logs:
  ```bash
  kubectl logs -n crystalshards deployment/crystalshards-api --tail=100
  ```
- Look for error messages related to webhook processing
- File an issue at https://github.com/crystalshards/monorepo/issues

### Webhook Succeeds but Version Not Indexed

**Cause:** Shard may not be registered, or version already exists

**Solutions:**
- Verify your shard is registered:
  ```bash
  curl https://crystalshards.org/api/shards/your-shard-name
  ```
- Check if the version already exists (webhooks are idempotent)
- Check worker logs for indexing errors:
  ```bash
  kubectl logs -n crystalshards deployment/crystalshards-worker --tail=100
  ```

### Version Number Not Recognized

**Cause:** Tag name doesn't match semantic versioning

**Solutions:**
- Use semantic version format: `v1.2.3` or `1.2.3`
- Ensure tag has three parts: major.minor.patch
- Avoid pre-release tags for now (e.g., `v1.0.0-alpha`)

## Security

### Signature Verification

CrystalShards uses HMAC SHA256 signature verification to ensure webhooks come from GitHub:

1. GitHub signs the payload with the shared secret
2. GitHub sends the signature in the `X-Hub-Signature-256` header
3. CrystalShards computes the expected signature
4. CrystalShards uses constant-time comparison to prevent timing attacks
5. Only webhooks with valid signatures are processed

### Rate Limiting

GitHub webhooks are not rate-limited by CrystalShards, but GitHub may impose limits on webhook delivery:

- GitHub retries failed webhook deliveries
- GitHub may disable webhooks that consistently fail
- Keep your webhook endpoint healthy to avoid being disabled

## Advanced Configuration

### Multiple Repositories

If you maintain multiple shards, add the webhook to each repository individually. Each webhook will use the same shared secret.

### Webhook Events

**Recommended events:**
- **Releases** - Triggered when you publish a release (most common)

**Optional events:**
- **Pushes** - Only processes tag pushes (ignores branch pushes)

### Idempotency

CrystalShards webhooks are idempotent:
- Duplicate webhook deliveries are safely ignored
- If a version is already indexed, it won't be re-indexed
- You can safely re-deliver webhooks from GitHub's interface

### Custom Tags

The webhook normalizes version tags:
- `v1.0.0` → `1.0.0` (removes `v` prefix)
- `1.0.0` → `1.0.0` (no change)

## API Reference

### Endpoint

```
POST /api/webhooks/github
```

### Headers

| Header | Required | Description |
|--------|----------|-------------|
| `X-GitHub-Event` | Yes | Event type (`release` or `push`) |
| `X-Hub-Signature-256` | Yes | HMAC SHA256 signature |
| `Content-Type` | Yes | Must be `application/json` |

### Request Body (Release Event)

```json
{
  "action": "published",
  "release": {
    "tag_name": "v1.0.0",
    "name": "Release 1.0.0"
  },
  "repository": {
    "full_name": "owner/repo-name",
    "html_url": "https://github.com/owner/repo-name"
  }
}
```

### Request Body (Tag Push Event)

```json
{
  "ref": "refs/tags/v1.0.0",
  "repository": {
    "full_name": "owner/repo-name",
    "html_url": "https://github.com/owner/repo-name"
  }
}
```

### Response

```json
{
  "status": "ok",
  "message": "Webhook received"
}
```

**Status Code:** Always `200 OK` (even for ignored events)

## Support

For issues or questions:
- File an issue: https://github.com/crystalshards/monorepo/issues
- Check logs: `kubectl logs -n crystalshards deployment/crystalshards-api`
- Contact: support@crystalshards.org

## Related Documentation

- [GitHub Webhooks Documentation](https://docs.github.com/en/webhooks)
- [CrystalShards API Documentation](https://crystalshards.org/api/docs)
- [Shard Publishing Guide](https://crystalshards.org/docs/publishing)
