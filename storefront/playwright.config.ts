import { defineConfig, devices } from '@playwright/test';

const port = 4331;

export default defineConfig({
  testDir: 'e2e',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  reporter: process.env.CI ? 'github' : 'list',
  use: { baseURL: `http://localhost:${port}`, locale: 'en-US', trace: 'retain-on-failure' },
  projects: [
    { name: 'phone', use: { ...devices['Pixel 7'] } },
    { name: 'desktop', use: { ...devices['Desktop Chrome'] } },
  ],
  // Builds the site and serves it with the built-in test catalog, so the
  // tests never touch the real shop. Wrangler runs it the way Cloudflare does.
  webServer: {
    command: `astro build && printf 'SHOP_DATA=fixtures\\n' > dist/server/.dev.vars && wrangler dev -c dist/server/wrangler.json --port ${port}`,
    url: `http://localhost:${port}`,
    timeout: 180_000,
    reuseExistingServer: false,
  },
});
