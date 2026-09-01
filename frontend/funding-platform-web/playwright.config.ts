import { defineConfig, devices } from '@playwright/test'

const externalBaseUrl = process.env.PLAYWRIGHT_BASE_URL?.replace(/\/$/, '')
const localBaseUrl = 'http://127.0.0.1:4173'

export default defineConfig({
  testDir: './e2e',
  fullyParallel: true,
  forbidOnly: Boolean(process.env.CI),
  failOnFlakyTests: Boolean(process.env.CI),
  retries: process.env.CI ? 1 : 0,
  workers: process.env.CI ? 1 : undefined,
  reporter: process.env.CI
    ? [['line'], ['html', { open: 'never' }]]
    : 'list',
  use: {
    baseURL: externalBaseUrl ?? localBaseUrl,
    screenshot: 'only-on-failure',
    trace: 'on-first-retry',
    video: 'off',
  },
  webServer: externalBaseUrl
    ? undefined
    : {
        command: 'npm run build && npm run preview -- --host 127.0.0.1 --port 4173 --strictPort',
        url: localBaseUrl,
        reuseExistingServer: !process.env.CI,
        timeout: 120_000,
        env: {
          VITE_API_BASE_URL: '/api/v1',
          VITE_EXTERNAL_AUTH_BASE_URL: '/api/v1',
          FUNDING_PLATFORM_API_PROXY_TARGET: 'http://127.0.0.1:9',
        },
      },
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
  ],
})
