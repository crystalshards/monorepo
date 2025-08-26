import { test, expect } from '@playwright/test';

// CrystalDocs Platform E2E Tests
test.describe('CrystalDocs Platform', () => {
  const baseURL = 'http://localhost:3001';

  test.beforeEach(async ({ page }) => {
    // Go to the docs homepage
    await page.goto(baseURL);
  });

  test('should load the documentation homepage', async ({ page }) => {
    await expect(page).toHaveTitle(/CrystalDocs/);
    await expect(page.locator('h1')).toContainText('CrystalDocs');
    await expect(page.locator('p')).toContainText('Crystal Package Documentation Platform');
  });

  test('should display search form on homepage', async ({ page }) => {
    // Check for search form
    await expect(page.locator('form[action="/search"]')).toBeVisible();
    await expect(page.locator('input[name="q"]')).toBeVisible();
    await expect(page.locator('button[type="submit"]')).toBeVisible();
  });

  test('should handle search functionality', async ({ page }) => {
    // Navigate to search page
    await page.goto(`${baseURL}/search`);
    
    await expect(page).toHaveTitle(/Search.*CrystalDocs/);
    await expect(page.locator('h1')).toContainText('CrystalDocs Search');
    await expect(page.locator('.suggestions')).toContainText('Popular Packages');
  });

  test('should perform search with query', async ({ page }) => {
    await page.goto(`${baseURL}/search?q=kemal`);
    
    await expect(page.locator('input[name="q"]')).toHaveValue('kemal');
    // Should show no results since database is empty
    await expect(page.locator('.no-results, .results-info')).toBeVisible();
  });

  test('should show search suggestions', async ({ page }) => {
    await page.goto(`${baseURL}/search`);
    
    await expect(page.locator('a[href="/search?q=kemal"]')).toBeVisible();
    await expect(page.locator('a[href="/search?q=crystal-pg"]')).toBeVisible();
    await expect(page.locator('a[href="/search?q=ameba"]')).toBeVisible();
  });

  test('should redirect package root to latest version', async ({ page }) => {
    const response = await page.request.get(`${baseURL}/docs/kemal`);
    expect(response.status()).toBe(302);
    
    const location = response.headers()['location'];
    expect(location).toBe('/docs/kemal/latest');
  });

  test('should show documentation not found page', async ({ page }) => {
    await page.goto(`${baseURL}/docs/nonexistent/latest`);
    
    await expect(page.locator('h3')).toContainText('Documentation Not Found');
    await expect(page.locator('button')).toContainText('Trigger Documentation Build');
  });

  test('should handle API endpoints', async ({ page }) => {
    // Test documentation API
    const response = await page.request.get(`${baseURL}/api/v1/docs/kemal`);
    expect(response.ok()).toBeTruthy();
    
    const data = await response.json();
    expect(data.package).toBe('kemal');
    expect(data.version).toBe('latest');
    expect(data.build_status).toBe('pending');
  });

  test('should support version parameter in API', async ({ page }) => {
    const response = await page.request.get(`${baseURL}/api/v1/docs/kemal?version=1.0.0`);
    expect(response.ok()).toBeTruthy();
    
    const data = await response.json();
    expect(data.version).toBe('1.0.0');
  });

  test('should handle build status API', async ({ page }) => {
    const response = await page.request.get(`${baseURL}/api/v1/docs/nonexistent/build-status`);
    expect(response.status()).toBe(404);
    
    const data = await response.json();
    expect(data.status).toBe('not_found');
  });

  test('should list all documentation builds', async ({ page }) => {
    const response = await page.request.get(`${baseURL}/api/v1/docs`);
    expect(response.ok()).toBeTruthy();
    
    const data = await response.json();
    expect(data.status).toBe('success');
    expect(data.count).toBeGreaterThanOrEqual(0);
    expect(Array.isArray(data.documentation)).toBeTruthy();
  });

  test('should support limit parameter in docs API', async ({ page }) => {
    const response = await page.request.get(`${baseURL}/api/v1/docs?limit=10`);
    expect(response.ok()).toBeTruthy();
    
    const data = await response.json();
    expect(data.status).toBe('success');
  });

  test('should return build statistics', async ({ page }) => {
    const response = await page.request.get(`${baseURL}/api/v1/build-stats`);
    expect(response.ok()).toBeTruthy();
    
    const data = await response.json();
    expect(data.status).toBe('success');
    expect(data.database_stats).toBeDefined();
    expect(typeof data.active_jobs).toBe('number');
    expect(typeof data.pending_jobs).toBe('number');
    expect(typeof data.total_jobs).toBe('number');
  });

  test('should check storage health', async ({ page }) => {
    const response = await page.request.get(`${baseURL}/api/v1/storage/health`);
    expect(response.ok()).toBeTruthy();
    
    const data = await response.json();
    expect(typeof data.storage_accessible).toBe('boolean');
    expect(data.timestamp).toBeDefined();
  });

  test('should handle documentation build requests', async ({ page }) => {
    const buildData = {
      shard_id: 1,
      version: '1.0.0',
      github_repo: 'test/package'
    };
    
    const response = await page.request.post(`${baseURL}/api/v1/docs/test-package/build`, {
      data: buildData,
      headers: {
        'Content-Type': 'application/json'
      }
    });
    
    // Should return success or error
    expect([200, 400, 500]).toContain(response.status());
    
    const data = await response.json();
    expect(data.status).toBeDefined();
  });

  test('should validate build request JSON', async ({ page }) => {
    const response = await page.request.post(`${baseURL}/api/v1/docs/test-package/build`, {
      data: 'invalid json',
      headers: {
        'Content-Type': 'application/json'
      }
    });
    
    expect(response.status()).toBe(400);
    
    const data = await response.json();
    expect(data.status).toBe('error');
    expect(data.message).toContain('Invalid request');
  });

  test('should return package versions', async ({ page }) => {
    const response = await page.request.get(`${baseURL}/api/v1/docs/nonexistent/versions`);
    expect(response.status()).toBe(404);
    
    const data = await response.json();
    expect(data.status).toBe('not_found');
    expect(data.message).toContain('Package \'nonexistent\' not found');
  });

  test('should list documentation files', async ({ page }) => {
    const response = await page.request.get(`${baseURL}/api/v1/docs/kemal/latest/files`);
    expect(response.ok()).toBeTruthy();
    
    const data = await response.json();
    expect(data.status).toBe('success');
    expect(data.package).toBe('kemal');
    expect(data.version).toBe('latest');
    expect(Array.isArray(data.files)).toBeTruthy();
  });

  test('should handle documentation content API', async ({ page }) => {
    const response = await page.request.get(`${baseURL}/api/v1/docs/nonexistent/latest/content`);
    expect(response.status()).toBe(404);
    
    const data = await response.json();
    expect(data.status).toBe('not_found');
  });

  test('should support file parameter in content API', async ({ page }) => {
    const response = await page.request.get(`${baseURL}/api/v1/docs/kemal/latest/content?file=index.html`);
    expect(response.status()).toBe(404); // Expected since no content exists
    
    const data = await response.json();
    expect(data.status).toBe('not_found');
  });

  test('should handle documentation metadata', async ({ page }) => {
    const response = await page.request.get(`${baseURL}/api/v1/docs/nonexistent/latest/metadata`);
    expect(response.status()).toBe(404);
    
    const data = await response.json();
    expect(data.status).toBe('not_found');
  });

  test('should set CORS headers', async ({ page }) => {
    const response = await page.request.get(`${baseURL}/api/v1/docs`);
    
    const headers = response.headers();
    expect(headers['access-control-allow-origin']).toBe('*');
    expect(headers['access-control-allow-methods']).toContain('GET');
    expect(headers['access-control-allow-headers']).toContain('Content-Type');
  });

  test('should handle OPTIONS requests', async ({ page }) => {
    const response = await page.request.fetch(`${baseURL}/api/v1/docs`, {
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

  test('should display custom 404 page', async ({ page }) => {
    await page.goto(`${baseURL}/nonexistent`);
    
    await expect(page.locator('h1')).toContainText('404 - Page Not Found');
    await expect(page.locator('a[href="/"]')).toContainText('Back to Home');
  });

  test('should handle search form submission', async ({ page }) => {
    await page.fill('input[name="q"]', 'crystal');
    await page.click('button[type="submit"]');
    
    await page.waitForURL(/\/search\?q=crystal/);
    await expect(page.locator('input[name="q"]')).toHaveValue('crystal');
  });

  test('should trigger build functionality', async ({ page }) => {
    await page.goto(`${baseURL}/docs/test-package/latest`);
    
    // Should show trigger build button
    await expect(page.locator('button')).toContainText('Trigger Documentation Build');
    
    // Test the triggerBuild function exists
    const triggerFunction = await page.evaluate(() => {
      return typeof window.triggerBuild === 'function';
    });
    expect(triggerFunction).toBeTruthy();
  });

  test('should be responsive on mobile', async ({ page, isMobile }) => {
    if (isMobile) {
      await expect(page.locator('.header')).toBeVisible();
      await expect(page.locator('input[name="q"]')).toBeVisible();
    }
  });
});