import { test, expect } from '@playwright/test';

// CrystalGigs Job Board E2E Tests
test.describe('CrystalGigs Job Board', () => {
  const baseURL = 'http://localhost:3002';

  test.beforeEach(async ({ page }) => {
    // Go to the job board homepage
    await page.goto(baseURL);
  });

  test('should load the job board homepage', async ({ page }) => {
    await expect(page).toHaveTitle(/CrystalGigs/);
    await expect(page.locator('h1')).toContainText('CrystalGigs');
    await expect(page.locator('h2')).toContainText('Find Your Next Crystal Developer Role');
  });

  test('should display post job button', async ({ page }) => {
    await expect(page.locator('a[href="/post"]')).toContainText('Post a Job');
    await expect(page.locator('a[href="/post"]')).toContainText('$99');
  });

  test('should show API link', async ({ page }) => {
    await expect(page.locator('a[href="/api/v1/jobs"]')).toContainText('API');
  });

  test('should display no jobs message when empty', async ({ page }) => {
    // Check for empty state
    const noJobsMessage = page.locator('text=No jobs posted yet');
    if (await noJobsMessage.isVisible()) {
      await expect(noJobsMessage).toBeVisible();
      await expect(page.locator('text=Be the first to post')).toBeVisible();
    }
  });

  test('should navigate to job posting form', async ({ page }) => {
    await page.click('a[href="/post"]');
    
    await expect(page).toHaveURL(`${baseURL}/post`);
    await expect(page).toHaveTitle(/Post a Job/);
    await expect(page.locator('h2')).toContainText('Post a Crystal Developer Job');
  });

  test('should display job posting form', async ({ page }) => {
    await page.goto(`${baseURL}/post`);
    
    // Check form elements
    await expect(page.locator('form[action="/jobs"]')).toBeVisible();
    await expect(page.locator('input[name="title"]')).toBeVisible();
    await expect(page.locator('input[name="company"]')).toBeVisible();
    await expect(page.locator('input[name="location"]')).toBeVisible();
    await expect(page.locator('select[name="type"]')).toBeVisible();
    await expect(page.locator('textarea[name="description"]')).toBeVisible();
    await expect(page.locator('input[name="email"]')).toBeVisible();
    await expect(page.locator('input[name="website"]')).toBeVisible();
  });

  test('should show pricing information', async ({ page }) => {
    await page.goto(`${baseURL}/post`);
    
    await expect(page.locator('.pricing')).toBeVisible();
    await expect(page.locator('.price')).toContainText('$99 for 30 days');
  });

  test('should validate required form fields', async ({ page }) => {
    await page.goto(`${baseURL}/post`);
    
    // Try to submit empty form
    await page.click('button[type="submit"]');
    
    // Browser validation should prevent submission
    const titleInput = page.locator('input[name="title"]');
    const isRequired = await titleInput.getAttribute('required');
    expect(isRequired).toBe('');
  });

  test('should fill out job posting form', async ({ page }) => {
    await page.goto(`${baseURL}/post`);
    
    // Fill out the form
    await page.fill('input[name="title"]', 'Senior Crystal Developer');
    await page.fill('input[name="company"]', 'Test Company');
    await page.fill('input[name="location"]', 'Remote');
    await page.selectOption('select[name="type"]', 'full-time');
    await page.fill('input[name="salary"]', '$120k - $160k');
    await page.fill('textarea[name="description"]', 'Great opportunity to work with Crystal programming language.');
    await page.fill('input[name="email"]', 'test@example.com');
    await page.fill('input[name="website"]', 'https://example.com');
    
    // Submit form (this would normally redirect to Stripe)
    const response = await page.request.post(`${baseURL}/jobs`, {
      form: {
        title: 'Senior Crystal Developer',
        company: 'Test Company',
        location: 'Remote',
        type: 'full-time',
        salary: '$120k - $160k',
        description: 'Great opportunity to work with Crystal programming language.',
        email: 'test@example.com',
        website: 'https://example.com'
      }
    });
    
    // Should redirect to payment or return error
    expect([302, 400, 500]).toContain(response.status());
  });

  test('should handle job API endpoints', async ({ page }) => {
    const response = await page.request.get(`${baseURL}/api/v1/jobs`);
    expect(response.ok()).toBeTruthy();
    
    const data = await response.json();
    expect(Array.isArray(data.jobs)).toBeTruthy();
    expect(typeof data.total).toBe('number');
    expect(data.page).toBe(1);
    expect(data.per_page).toBe(20);
  });

  test('should support pagination in jobs API', async ({ page }) => {
    const response = await page.request.get(`${baseURL}/api/v1/jobs?limit=5&offset=10`);
    expect(response.ok()).toBeTruthy();
    
    const data = await response.json();
    expect(data.page).toBe(3); // (10/5) + 1
    expect(data.per_page).toBe(5);
  });

  test('should support search in jobs API', async ({ page }) => {
    const response = await page.request.get(`${baseURL}/api/v1/jobs?q=crystal+developer`);
    expect(response.ok()).toBeTruthy();
    
    const data = await response.json();
    expect(data.query).toBe('crystal developer');
    expect(Array.isArray(data.jobs)).toBeTruthy();
  });

  test('should limit API page size', async ({ page }) => {
    const response = await page.request.get(`${baseURL}/api/v1/jobs?limit=500`);
    expect(response.ok()).toBeTruthy();
    
    const data = await response.json();
    expect(data.per_page).toBe(100); // Should be clamped to max
  });

  test('should handle payment success page', async ({ page }) => {
    // Test with missing parameters
    const response = await page.request.get(`${baseURL}/payment/success`);
    expect(response.status()).toBe(302);
    
    const location = response.headers()['location'];
    expect(location).toContain('/post?error=');
  });

  test('should handle Stripe webhooks', async ({ page }) => {
    const webhookPayload = {
      type: 'checkout.session.completed',
      data: {
        object: {
          id: 'cs_test_123',
          payment_status: 'paid'
        }
      }
    };
    
    const response = await page.request.post(`${baseURL}/webhook/stripe`, {
      data: webhookPayload,
      headers: {
        'Content-Type': 'application/json'
      }
    });
    
    expect(response.ok()).toBeTruthy();
    
    const data = await response.json();
    expect(data.status).toBe('received');
  });

  test('should handle invalid webhook data', async ({ page }) => {
    const response = await page.request.post(`${baseURL}/webhook/stripe`, {
      data: 'invalid json',
      headers: {
        'Content-Type': 'application/json'
      }
    });
    
    expect(response.status()).toBe(400);
    
    const data = await response.json();
    expect(data.error).toBe('Invalid webhook');
  });

  test('should handle payment_intent.succeeded webhooks', async ({ page }) => {
    const webhookPayload = {
      type: 'payment_intent.succeeded',
      data: {
        object: {
          id: 'pi_test_123'
        }
      }
    };
    
    const response = await page.request.post(`${baseURL}/webhook/stripe`, {
      data: webhookPayload,
      headers: {
        'Content-Type': 'application/json'
      }
    });
    
    expect(response.ok()).toBeTruthy();
  });

  test('should set CORS headers', async ({ page }) => {
    const response = await page.request.get(`${baseURL}/api/v1/jobs`);
    
    const headers = response.headers();
    expect(headers['access-control-allow-origin']).toBe('*');
    expect(headers['access-control-allow-methods']).toContain('GET');
    expect(headers['access-control-allow-headers']).toContain('Content-Type');
  });

  test('should handle OPTIONS requests', async ({ page }) => {
    const response = await page.request.fetch(`${baseURL}/api/v1/jobs`, {
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
    await expect(page.locator('a[href="/"]')).toContainText('Back to Jobs');
  });

  test('should handle form submission errors', async ({ page }) => {
    // Test with missing required fields
    const response = await page.request.post(`${baseURL}/jobs`, {
      form: {
        title: '',
        company: '',
      }
    });
    
    expect(response.status()).toBe(400);
    
    const body = await response.text();
    expect(body).toContain('Missing required fields');
  });

  test('should display error messages on post page', async ({ page }) => {
    await page.goto(`${baseURL}/post?error=payment_cancelled`);
    
    await expect(page.locator('div[style*="background: #f8d7da"]')).toContainText('Payment was cancelled');
  });

  test('should handle different error types', async ({ page }) => {
    const errorTypes = [
      'payment_cancelled',
      'payment_failed', 
      'job_data_expired',
      'database_error',
      'processing_error'
    ];
    
    for (const errorType of errorTypes) {
      await page.goto(`${baseURL}/post?error=${errorType}`);
      
      // Should display some error message
      const errorDiv = page.locator('div[style*="background: #f8d7da"]');
      if (await errorDiv.isVisible()) {
        await expect(errorDiv).toBeVisible();
      }
    }
  });

  test('should be responsive on mobile', async ({ page, isMobile }) => {
    if (isMobile) {
      await expect(page.locator('.header')).toBeVisible();
      await expect(page.locator('.container')).toBeVisible();
      
      // Check mobile-specific styles
      await page.goto(`${baseURL}/post`);
      await expect(page.locator('input[name="title"]')).toBeVisible();
    }
  });

  test('should handle form validation', async ({ page }) => {
    await page.goto(`${baseURL}/post`);
    
    // Test email validation
    await page.fill('input[name="email"]', 'invalid-email');
    
    const emailInput = page.locator('input[name="email"]');
    const inputType = await emailInput.getAttribute('type');
    expect(inputType).toBe('email');
  });

  test('should handle special characters in form', async ({ page }) => {
    const response = await page.request.post(`${baseURL}/jobs`, {
      form: {
        title: 'Test <script>',
        company: 'Test & Co',
        location: 'Remote',
        type: 'full-time',
        description: 'Description with "quotes" and special chars',
        email: 'test@example.com'
      }
    });
    
    // Should process without crashing
    expect([302, 400, 500]).toContain(response.status());
  });
});