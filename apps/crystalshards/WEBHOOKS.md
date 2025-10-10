# GitHub Webhook Configuration for Automatic Shard Indexing

CrystalShards.org supports automatic indexing of new shard versions through GitHub webhooks. When you publish a new release or push a new tag to your repository, GitHub will notify CrystalShards, which will automatically index the new version.

## Overview

The webhook endpoint accepts the following GitHub events:
- **Release Published** - Triggered when you create a new release on GitHub
- **Tag Push** - Triggered when you push a new tag to your repository

## Prerequisites

1. Your shard must already be registered on CrystalShards.org
2. You must have admin access to the GitHub repository
3. Your repository must contain a valid `shard.yml` file

## Setting Up the Webhook

### Step 1: Get the Webhook Secret

Contact the CrystalShards.org administrators to get your webhook secret, or retrieve it from the Kubernetes cluster:

```bash
kubectl get secret crystalshards-secrets -n crystalshards -o jsonpath='{.data.github_webhook_secret}' | base64 -d
```

### Step 2: Configure Webhook on GitHub

1. Go to your repository on GitHub
2. Click **Settings** → **Webhooks** → **Add webhook**
3. Configure the webhook with the following settings:

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
[Enter the webhook secret from Step 1]
```

**Which events would you like to trigger this webhook?**
- Select "Let me select individual events"
- Check **Releases**
- Check **Pushes** (optional - for tag pushes)
- Uncheck everything else

**Active:**
- Check "Active"

4. Click **Add webhook**

### Step 3: Test the Webhook

#### Option 1: Publish a Release

1. Go to your repository on GitHub
2. Click **Releases** → **Create a new release**
3. Enter a tag version (e.g., `v1.0.0` or `1.0.0`)
4. Enter release details
5. Click **Publish release**

#### Option 2: Push a Tag

```bash
git tag v1.0.0
git push origin v1.0.0
```

### Step 4: Verify Webhook Delivery

1. Go to your repository on GitHub
2. Click **Settings** → **Webhooks**
3. Click on the webhook you created
4. Scroll down to **Recent Deliveries**
5. Check that the webhook was delivered successfully (status 200)

## How It Works

### 1. Webhook Event Received

When GitHub sends a webhook event, CrystalShards.org:
1. Verifies the webhook signature using HMAC SHA256
2. Extracts the event type (release or push)
3. Parses the payload to get repository and version information

### 2. Event Processing

For **Release Published** events:
- Extracts tag name from `release.tag_name`
- Extracts repository from `repository.full_name`

For **Tag Push** events:
- Checks if the push is for a tag (`refs/tags/*`)
- Extracts tag name from `ref`
- Extracts repository from `repository.full_name`

### 3. Version Normalization

- Version prefixes (`v1.0.0`) are normalized to `1.0.0`
- Shard name is extracted from the repository name (e.g., `owner/repo-name` → `repo-name`)

### 4. Idempotency Check

Before indexing, CrystalShards checks if the version already exists:
- If the version exists, the webhook is acknowledged but no indexing occurs
- If the version is new, the IndexShardWorker is enqueued

### 5. Background Processing

The IndexShardWorker:
1. Fetches the `shard.yml` from your repository at the specified tag
2. Parses dependencies and metadata
3. Updates the shard information in the database
4. Triggers documentation build (BuildDocsWorker)
5. Updates dependency graph (UpdateDependenciesWorker)

## Webhook Signature Verification

CrystalShards.org uses HMAC SHA256 to verify webhook signatures. This ensures that webhook requests are genuinely from GitHub and haven't been tampered with.

The signature is sent in the `X-Hub-Signature-256` header:
```
X-Hub-Signature-256: sha256=<signature>
```

The signature is computed as:
```
HMAC-SHA256(secret, request_body)
```

Invalid signatures are rejected with a 401 Unauthorized response.

## Webhook Payload Examples

### Release Published Event

```json
{
  "action": "published",
  "release": {
    "tag_name": "v1.2.3",
    "name": "Release 1.2.3"
  },
  "repository": {
    "full_name": "owner/my-shard",
    "html_url": "https://github.com/owner/my-shard"
  }
}
```

### Tag Push Event

```json
{
  "ref": "refs/tags/v1.2.3",
  "repository": {
    "full_name": "owner/my-shard",
    "html_url": "https://github.com/owner/my-shard"
  }
}
```

## Response Codes

- **200 OK** - Webhook received and processed successfully (or already indexed)
- **401 Unauthorized** - Invalid or missing signature
- **400 Bad Request** - Invalid payload format

## Troubleshooting

### Webhook Shows 401 Unauthorized

**Cause:** Invalid webhook secret

**Solution:**
1. Verify that the webhook secret in GitHub matches the one in Kubernetes
2. Re-enter the secret in GitHub webhook settings
3. Test the webhook again

### Webhook Shows 200 but Shard Version Not Indexed

**Possible Causes:**
1. Shard not registered on CrystalShards.org
2. Version already exists (idempotency check passed)
3. Invalid `shard.yml` in repository
4. Background worker processing failed

**Solution:**
1. Verify your shard is registered: `https://crystalshards.org/shards/your-shard-name`
2. Check if the version already exists
3. Verify `shard.yml` is valid and committed at the tag
4. Check worker logs in Kubernetes:
   ```bash
   kubectl logs -n crystalshards -l app=crystalshards-worker --tail=100
   ```

### Tag Push Events Not Working

**Cause:** Webhook not configured for push events

**Solution:**
1. Go to webhook settings on GitHub
2. Edit the webhook
3. Ensure "Pushes" is checked under event triggers
4. Save the webhook

### Release Events Not Working

**Cause:** Webhook not configured for release events

**Solution:**
1. Go to webhook settings on GitHub
2. Edit the webhook
3. Ensure "Releases" is checked under event triggers
4. Save the webhook

## Manual Indexing

If webhooks fail or you prefer manual indexing, you can use the CrystalShards.org web interface:

1. Go to `https://crystalshards.org/shards/your-shard-name`
2. Click "Add Version" or "Sync from GitHub"
3. Enter the version number
4. Click "Index Version"

## Security Considerations

1. **Keep Webhook Secret Secure** - Never commit the webhook secret to your repository
2. **Signature Verification** - CrystalShards.org always verifies webhook signatures
3. **Constant-Time Comparison** - Signature verification uses constant-time comparison to prevent timing attacks
4. **HTTPS Only** - Webhooks are only accepted over HTTPS

## Additional Resources

- [GitHub Webhooks Documentation](https://docs.github.com/en/webhooks)
- [Crystal Shards Specification](https://github.com/crystal-lang/shards/blob/master/docs/shard.yml.adoc)
- [CrystalShards.org API Documentation](https://crystalshards.org/api/docs)

## Support

If you encounter issues with webhook configuration:
1. Check webhook delivery logs on GitHub
2. Check CrystalShards.org logs (if you have access)
3. Open an issue on the CrystalShards.org GitHub repository
4. Contact the CrystalShards.org team

## Example: Complete Setup

Here's a complete example of setting up webhooks for a shard called "my-awesome-shard":

```bash
# 1. Register your shard on CrystalShards.org (via web UI)

# 2. Get webhook secret (if you have kubectl access)
export WEBHOOK_SECRET=$(kubectl get secret crystalshards-secrets -n crystalshards -o jsonpath='{.data.github_webhook_secret}' | base64 -d)

# 3. Configure webhook on GitHub (via web UI):
#    - Payload URL: https://crystalshards.org/api/webhooks/github
#    - Content type: application/json
#    - Secret: $WEBHOOK_SECRET
#    - Events: Releases, Pushes

# 4. Create and push a tag
git tag v1.0.0
git push origin v1.0.0

# 5. Verify on CrystalShards.org
curl https://crystalshards.org/api/shards/my-awesome-shard/versions/1.0.0
```

The shard version should be indexed automatically within a few minutes.
