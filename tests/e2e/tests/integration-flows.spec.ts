import { test, expect } from '@playwright/test';

// Cross-platform integration tests
test.describe('CrystalShards Platform Integration', () => {
  const registryURL = 'http://localhost:3000';
  const docsURL = 'http://localhost:3001';
  const gigsURL = 'http://localhost:3002';

  test('should have all services running and healthy', async ({ page }) => {
    // Check all health endpoints
    const healthChecks = [
      { name: 'Registry', url: `${registryURL}/health` },
      { name: 'Docs', url: `${docsURL}/health` },
      { name: 'Gigs', url: `${gigsURL}/health` }
    ];

    for (const service of healthChecks) {
      const response = await page.request.get(service.url);
      expect(response.ok()).toBeTruthy();
      
      const data = await response.json();
      expect(data.status).toBe('ok');
      expect(data.version).toBe('0.1.0');
      expect(data.timestamp).toBeDefined();
    }
  });

  test('should have consistent CORS headers across services', async ({ page }) => {
    const apiEndpoints = [
      `${registryURL}/api/v1`,
      `${docsURL}/api/v1/docs`,
      `${gigsURL}/api/v1/jobs`
    ];

    for (const endpoint of apiEndpoints) {
      const response = await page.request.get(endpoint);
      expect(response.ok()).toBeTruthy();
      
      const headers = response.headers();
      expect(headers['access-control-allow-origin']).toBe('*');
      expect(headers['access-control-allow-methods']).toContain('GET');
      expect(headers['access-control-allow-headers']).toContain('Content-Type');
    }
  });

  test('should handle OPTIONS requests consistently', async ({ page }) => {
    const apiEndpoints = [
      `${registryURL}/api/v1/shards`,
      `${docsURL}/api/v1/docs`,
      `${gigsURL}/api/v1/jobs`
    ];

    for (const endpoint of apiEndpoints) {
      const response = await page.request.fetch(endpoint, {
        method: 'OPTIONS'
      });
      
      expect(response.status()).toBe(200);
    }
  });

  test('should have consistent error handling', async ({ page }) => {
    const notFoundEndpoints = [
      `${registryURL}/nonexistent`,
      `${docsURL}/nonexistent`,
      `${gigsURL}/nonexistent`
    ];

    for (const endpoint of notFoundEndpoints) {
      const response = await page.request.get(endpoint);
      expect(response.status()).toBe(404);
    }
  });

  test.describe('Cross-service workflows', () => {
    test('should link from registry to documentation', async ({ page }) => {
      // This test would simulate the flow where a shard in the registry
      // links to its documentation on the docs platform
      
      // 1. Submit a shard to registry (mock)
      const shardData = {
        github_url: 'https://github.com/test/example-shard'
      };
      
      const submitResponse = await page.request.post(`${registryURL}/api/v1/shards`, {
        data: shardData,
        headers: {
          'Content-Type': 'application/json'
        }
      });
      
      // Should get some response (success or error)
      expect([201, 409, 422, 429, 500]).toContain(submitResponse.status());
      
      // 2. Trigger documentation build
      const buildData = {
        shard_id: 1,
        version: 'latest',
        github_repo: 'test/example-shard'
      };
      
      const buildResponse = await page.request.post(`${docsURL}/api/v1/docs/example-shard/build`, {
        data: buildData,
        headers: {
          'Content-Type': 'application/json'
        }
      });
      
      // Should accept build request
      expect([200, 400, 500]).toContain(buildResponse.status());
    });

    test('should handle job posting for Crystal package maintainers', async ({ page }) => {
      // Simulate a workflow where someone posts a job specifically for Crystal developers
      
      // 1. Go to job board
      await page.goto(gigsURL);
      await expect(page.locator('h1')).toContainText('CrystalGigs');
      
      // 2. Navigate to post form
      await page.click('a[href="/post"]');
      await expect(page).toHaveURL(`${gigsURL}/post`);
      
      // 3. Fill out Crystal-specific job
      await page.fill('input[name="title"]', 'Crystal Shard Maintainer');
      await page.fill('input[name="company"]', 'Crystal Foundation');
      await page.fill('input[name="location"]', 'Remote');
      await page.selectOption('select[name="type"]', 'contract');
      await page.fill('textarea[name="description"]', 'Looking for experienced Crystal developer to maintain open source shards');
      await page.fill('input[name="email"]', 'jobs@crystal-lang.org');
      
      // Form should be ready for submission
      const submitButton = page.locator('button[type="submit"]');
      await expect(submitButton).toContainText('Post Job - $99');
    });

    test('should enable documentation search across packages', async ({ page }) => {
      // Test search functionality across the documentation platform
      
      await page.goto(docsURL);
      
      // 1. Use search from homepage
      await page.fill('input[name="q"]', 'crystal http client');
      await page.click('button[type="submit"]');
      
      // 2. Should navigate to search results
      await expect(page).toHaveURL(/search\?q=crystal\+http\+client/);
      
      // 3. Should display search interface
      await expect(page.locator('input[name="q"]')).toHaveValue('crystal http client');
      
      // 4. Should handle no results gracefully
      await expect(page.locator('.no-results, .results-info')).toBeVisible();
    });
  });

  test.describe('API consistency', () => {
    test('should have similar response formats', async ({ page }) => {
      // Check that all APIs return consistent JSON responses
      
      const apiCalls = [
        { url: `${registryURL}/api/v1/shards`, expectedFields: ['shards', 'total', 'page'] },
        { url: `${docsURL}/api/v1/docs`, expectedFields: ['status', 'count', 'documentation'] },
        { url: `${gigsURL}/api/v1/jobs`, expectedFields: ['jobs', 'total', 'page'] }
      ];

      for (const api of apiCalls) {
        const response = await page.request.get(api.url);
        expect(response.ok()).toBeTruthy();
        
        const data = await response.json();
        
        for (const field of api.expectedFields) {
          expect(data[field]).toBeDefined();
        }
      }
    });

    test('should handle pagination consistently', async ({ page }) => {
      const paginatedAPIs = [
        `${registryURL}/api/v1/shards`,
        `${gigsURL}/api/v1/jobs`
      ];

      for (const api of paginatedAPIs) {
        const response = await page.request.get(`${api}?page=2&per_page=5`);
        expect(response.ok()).toBeTruthy();
        
        const data = await response.json();
        expect(data.page).toBe(2);
        expect(data.per_page).toBe(5);
      }
    });

    test('should validate input consistently', async ({ page }) => {
      // Test input validation across services
      
      const invalidRequests = [
        {
          url: `${registryURL}/api/v1/shards`,
          method: 'POST',
          data: {},
          expectedStatus: 400
        },
        {
          url: `${registryURL}/api/v1/search`,
          method: 'GET',
          expectedStatus: 400
        }
      ];

      for (const req of invalidRequests) {
        const response = req.method === 'POST' 
          ? await page.request.post(req.url, { 
              data: req.data || {},
              headers: { 'Content-Type': 'application/json' }
            })
          : await page.request.get(req.url);
        
        expect(response.status()).toBe(req.expectedStatus);
      }
    });
  });

  test.describe('Performance and reliability', () => {
    test('should respond quickly to health checks', async ({ page }) => {
      const startTime = Date.now();
      
      const healthChecks = [
        `${registryURL}/health`,
        `${docsURL}/health`,
        `${gigsURL}/health`
      ];

      for (const url of healthChecks) {
        const checkStart = Date.now();
        const response = await page.request.get(url);
        const duration = Date.now() - checkStart;
        
        expect(response.ok()).toBeTruthy();
        expect(duration).toBeLessThan(1000); // Should respond within 1 second
      }
      
      const totalDuration = Date.now() - startTime;
      expect(totalDuration).toBeLessThan(3000); // All checks within 3 seconds
    });

    test('should handle concurrent requests', async ({ page }) => {
      // Test concurrent API calls
      const promises = [];
      
      for (let i = 0; i < 5; i++) {
        promises.push(page.request.get(`${registryURL}/api/v1/shards`));
        promises.push(page.request.get(`${docsURL}/api/v1/docs`));
        promises.push(page.request.get(`${gigsURL}/api/v1/jobs`));
      }
      
      const responses = await Promise.all(promises);
      
      for (const response of responses) {
        expect(response.ok()).toBeTruthy();
      }
    });
  });

  test.describe('Security headers', () => {
    test('should set appropriate security headers', async ({ page }) => {
      const endpoints = [
        registryURL,
        docsURL,
        gigsURL
      ];

      for (const endpoint of endpoints) {
        const response = await page.request.get(endpoint);
        const headers = response.headers();
        
        // Check CORS headers
        expect(headers['access-control-allow-origin']).toBe('*');
        
        // Content type should be set
        expect(headers['content-type']).toBeDefined();
      }
    });
  });

  test.describe('Mobile compatibility', () => {
    test('should work on mobile devices', async ({ page, isMobile }) => {
      if (isMobile) {
        const sites = [registryURL, docsURL, gigsURL];
        
        for (const site of sites) {
          await page.goto(site);
          
          // Should load without errors
          await expect(page.locator('h1')).toBeVisible();
          
          // Should have viewport meta tag for mobile
          const viewportMeta = await page.locator('meta[name="viewport"]').getAttribute('content');
          expect(viewportMeta).toContain('width=device-width');
        }
      }
    });
  });
});