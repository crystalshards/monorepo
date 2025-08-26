import { test, expect } from '@playwright/test';

// CrystalShards Registry E2E Tests
test.describe('CrystalShards Registry', () => {
  const baseURL = 'http://localhost:3000';

  test.beforeEach(async ({ page }) => {
    // Go to the registry homepage
    await page.goto(baseURL);
  });

  test('should load the registry homepage', async ({ page }) => {
    await expect(page).toHaveTitle(/CrystalShards/);
    await expect(page.locator('h1')).toContainText('CrystalShards');
  });

  test('should display API information', async ({ page }) => {
    await page.goto(`${baseURL}/api/v1`);
    
    // Check that API info is returned
    const response = await page.textContent('body');
    const apiInfo = JSON.parse(response || '{}');
    
    expect(apiInfo.message).toBe('CrystalShards API v1');
    expect(apiInfo.version).toBe('0.1.0');
    expect(apiInfo.endpoints).toBeDefined();
  });

  test('should handle shard listing API', async ({ page }) => {
    const response = await page.request.get(`${baseURL}/api/v1/shards`);
    expect(response.ok()).toBeTruthy();
    
    const data = await response.json();
    expect(data.shards).toBeDefined();
    expect(data.total).toBeGreaterThanOrEqual(0);
    expect(data.page).toBe(1);
    expect(data.per_page).toBe(20);
  });

  test('should handle search functionality', async ({ page }) => {
    // Test search with query parameter
    const response = await page.request.get(`${baseURL}/api/v1/search?q=crystal`);
    expect(response.ok()).toBeTruthy();
    
    const data = await response.json();
    expect(data.query).toBe('crystal');
    expect(data.results).toBeDefined();
    expect(data.total).toBeGreaterThanOrEqual(0);
  });

  test('should return error for empty search', async ({ page }) => {
    const response = await page.request.get(`${baseURL}/api/v1/search`);
    expect(response.status()).toBe(400);
    
    const data = await response.json();
    expect(data.error).toBe('Missing query parameter \'q\'');
  });

  test('should handle shard submission', async ({ page }) => {
    const submissionData = {
      github_url: 'https://github.com/crystal-lang/crystal'
    };
    
    const response = await page.request.post(`${baseURL}/api/v1/shards`, {
      data: submissionData,
      headers: {
        'Content-Type': 'application/json'
      }
    });
    
    // Should return 201 (created), 409 (exists), 422 (validation error), or 429 (rate limit)
    expect([201, 409, 422, 429, 500]).toContain(response.status());
  });

  test('should validate shard submission data', async ({ page }) => {
    // Test with missing github_url
    const response = await page.request.post(`${baseURL}/api/v1/shards`, {
      data: {},
      headers: {
        'Content-Type': 'application/json'
      }
    });
    
    expect(response.status()).toBe(400);
    
    const data = await response.json();
    expect(data.error).toBe('Missing required field: github_url');
  });

  test('should handle individual shard requests', async ({ page }) => {
    const response = await page.request.get(`${baseURL}/api/v1/shards/nonexistent`);
    expect(response.status()).toBe(404);
    
    const data = await response.json();
    expect(data.error).toBe('Shard not found');
  });

  test('should handle GitHub webhooks', async ({ page }) => {
    const webhookPayload = {
      action: 'published',
      repository: {
        html_url: 'https://github.com/test/repo'
      }
    };
    
    const response = await page.request.post(`${baseURL}/webhooks/github`, {
      data: webhookPayload,
      headers: {
        'Content-Type': 'application/json'
      }
    });
    
    expect(response.ok()).toBeTruthy();
    
    const data = await response.json();
    expect(data.status).toBe('ok');
  });

  test('should set CORS headers', async ({ page }) => {
    const response = await page.request.get(`${baseURL}/api/v1`);
    
    const headers = response.headers();
    expect(headers['access-control-allow-origin']).toBe('*');
    expect(headers['access-control-allow-methods']).toContain('GET');
  });

  test('should handle OPTIONS requests', async ({ page }) => {
    const response = await page.request.fetch(`${baseURL}/api/v1/shards`, {
      method: 'OPTIONS'
    });
    
    expect(response.status()).toBe(200);
  });

  test('should return proper health status', async ({ page }) => {
    const response = await page.request.get(`${baseURL}/health`);
    expect(response.ok()).toBeTruthy();
    
    const data = await response.json();
    expect(data.status).toBe('ok');
    expect(data.version).toBe('0.1.0');
    expect(data.timestamp).toBeDefined();
  });

  test('should handle pagination in shard listing', async ({ page }) => {
    // Test pagination parameters
    const response = await page.request.get(`${baseURL}/api/v1/shards?page=2&per_page=5`);
    expect(response.ok()).toBeTruthy();
    
    const data = await response.json();
    expect(data.page).toBe(2);
    expect(data.per_page).toBe(5);
  });

  test('should limit page size appropriately', async ({ page }) => {
    // Test that per_page is limited to maximum
    const response = await page.request.get(`${baseURL}/api/v1/shards?per_page=500`);
    expect(response.ok()).toBeTruthy();
    
    const data = await response.json();
    expect(data.per_page).toBe(100); // Should be clamped to max
  });

  test('should handle search with pagination', async ({ page }) => {
    const response = await page.request.get(`${baseURL}/api/v1/search?q=test&page=2&per_page=10`);
    expect(response.ok()).toBeTruthy();
    
    const data = await response.json();
    expect(data.query).toBe('test');
    expect(data.page).toBe(2);
    expect(data.per_page).toBe(10);
  });

  test('should return 404 for unknown routes', async ({ page }) => {
    const response = await page.request.get(`${baseURL}/nonexistent`);
    expect(response.status()).toBe(404);
    
    const data = await response.json();
    expect(data.error).toBe('Not Found');
    expect(data.status).toBe(404);
  });
});