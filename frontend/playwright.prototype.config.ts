import { defineConfig, devices } from '@playwright/test'

const hostedUrl = process.env.DOCAYA_E2E_URL

export default defineConfig({
  testDir: './tests/prototype',
  fullyParallel: false,
  workers: 1,
  timeout: 60_000,
  expect: { timeout: 10_000 },
  reporter: 'line',
  use: { baseURL: hostedUrl || 'http://127.0.0.1:4174', trace: 'retain-on-failure' },
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'], channel: process.env.CI ? undefined : 'chrome' },
    },
  ],
  webServer: hostedUrl
    ? undefined
    : {
        command: 'npx vite --host 127.0.0.1 --port 4174 --strictPort',
        url: 'http://127.0.0.1:4174',
        reuseExistingServer: !process.env.CI,
      },
})
