import { test, expect, type Page } from '@playwright/test'
import AxeBuilder from '@axe-core/playwright'
import { readFile } from 'node:fs/promises'

async function signIn(page: Page) {
  await page.goto('./')
  await page.getByRole('button', { name: 'Enter demo workspace', exact: true }).click()
}
async function navigate(page: Page, name: string) {
  await page.locator('nav').getByRole('button', { name, exact: true }).click()
}

test('register, approve, index, cite, hold and restore the original bytes', async ({ page }) => {
  const errors: string[] = []
  page.on('pageerror', (e) => errors.push(e.message))
  await signIn(page)
  await page.getByRole('button', { name: 'Register document', exact: true }).click()
  await page.getByLabel('Choose file', { exact: true }).setInputFiles({
    name: 'client-workshop-memo.txt',
    mimeType: 'text/plain',
    buffer: Buffer.from(
      'DOCAYA SAMPLE\nClient workshop memorandum\nProposed service improvements for client review.',
    ),
  })
  await page.getByRole('button', { name: 'Continue', exact: true }).click()
  await page.getByLabel('Business title *', { exact: true }).fill('Client workshop memorandum')
  await page.getByLabel('Document class *').selectOption('Memo')
  await page
    .getByLabel('Description *')
    .fill('Workshop governance requires every memorandum to be classified and approved.')
  await page.getByRole('button', { name: 'Continue', exact: true }).click()
  await page.getByLabel('I have reviewed the document and classification').check()
  await page.getByRole('button', { name: 'Submit for approval', exact: true }).click()
  await page.getByRole('button', { name: /Client workshop memorandum.*DOC-/ }).click()
  await page.getByRole('dialog').getByRole('button', { name: 'Review', exact: true }).click()
  await page.getByRole('button', { name: 'Approve & sign', exact: true }).click()
  await expect(page.getByRole('dialog').getByText('Published', { exact: true })).toBeVisible()
  await page.getByRole('dialog').getByRole('button', { name: 'Details', exact: true }).click()
  const downloadPromise = page.waitForEvent('download')
  await page.getByRole('button', { name: 'Download original / sample' }).click()
  const download = await downloadPromise
  expect(download.suggestedFilename()).toBe('client-workshop-memo.txt')
  expect(await readFile((await download.path())!, 'utf8')).toBe(
    'DOCAYA SAMPLE\nClient workshop memorandum\nProposed service improvements for client review.',
  )
  await page.getByRole('button', { name: 'Close review drawer', exact: true }).click()
  await navigate(page, 'Staging & publishing')
  await page.getByRole('button', { name: 'Search indexing', exact: true }).click()
  await page.getByRole('button', { name: 'Run demo batch', exact: true }).click()
  await expect(page.getByRole('button', { name: 'Run demo batch', exact: true })).toBeEnabled()
  await navigate(page, 'Search & Ask Docaya')
  await page.getByRole('textbox', { name: 'Ask Docaya question' }).fill('workshop memorandum')
  await page.getByRole('button', { name: 'Ask Docaya', exact: true }).click()
  await page.locator('.p-citation').filter({ hasText: 'Client workshop memorandum' }).click()
  await page.getByRole('button', { name: 'Governance', exact: true }).click()
  await page.getByLabel('Governance reason / case reference').fill('LH-DEMO-17 · Client review')
  await page.getByRole('button', { name: 'Apply legal hold', exact: true }).click()
  await expect(page.getByRole('button', { name: 'Archive record', exact: true })).toBeDisabled()
  await page.getByRole('button', { name: 'Close', exact: true }).click()
  await page.reload()
  await navigate(page, 'Records & retention')
  await page.getByRole('button', { name: 'Legal holds', exact: true }).click()
  await expect(page.getByRole('button', { name: /Client workshop memorandum.*DOC-/ })).toBeVisible()
  expect(errors).toEqual([])
})

test('role trimming, global search, correspondence and workshop persistence', async ({ page }) => {
  await signIn(page)
  await page.getByRole('combobox', { name: 'Demo persona', exact: true }).selectOption('Viewer')
  await expect(page.getByRole('button', { name: 'Register document', exact: true })).toHaveCount(0)
  await navigate(page, 'Document register')
  await expect(page.getByText('Restricted case assessment', { exact: true })).toHaveCount(0)
  await expect(page.getByText('Employee onboarding checklist', { exact: true })).toHaveCount(0)
  await page.getByRole('textbox', { name: 'Global search', exact: true }).fill('continuity')
  await page.getByRole('textbox', { name: 'Global search', exact: true }).press('Enter')
  await expect(page.getByRole('button', { name: /Preview Business continuity/ })).toBeVisible()
  await page.getByRole('button', { name: 'List view', exact: true }).click()
  await expect(page.locator('tbody tr').filter({ hasText: 'Business continuity' })).toHaveCount(1)
  await page.getByRole('combobox', { name: 'Demo persona', exact: true }).selectOption('System Administrator')
  await navigate(page, 'Correspondence')
  await page.getByRole('button', { name: 'New correspondence', exact: true }).click()
  await page.getByLabel('Subject *', { exact: true }).fill('Client briefing')
  await page.getByLabel('Sender / recipient *').fill('Client office')
  await page.getByLabel('Due date *').fill('2026-12-01')
  await page.getByLabel('Message *', { exact: true }).fill('Please review the prototype.')
  await page.getByRole('button', { name: 'Register correspondence', exact: true }).click()
  await page.getByLabel('Reply / action note').fill('Review is scheduled.')
  await page.getByRole('button', { name: 'Record reply', exact: true }).click()
  await expect(page.getByText(/Review is scheduled/)).toBeVisible()
  await page.getByRole('button', { name: 'Close / إغلاق', exact: true }).click()
  await navigate(page, 'Client workshop')
  await page
    .getByLabel('Expectation / decision')
    .fill('Client wants a department-specific approval dashboard.')
  await page.getByRole('button', { name: 'Save feedback', exact: true }).click()
  await page.reload()
  await navigate(page, 'Client workshop')
  await expect(
    page.getByText('Client wants a department-specific approval dashboard.', { exact: true }),
  ).toBeVisible()
})

test('administration config, recovery, notifications and reporting exports', async ({ page }) => {
  await signIn(page)
  await navigate(page, 'Admin center')
  await page.getByRole('textbox', { name: 'New document class', exact: true }).fill('Client Charter')
  await page.getByRole('button', { name: 'Add', exact: true }).click()
  await page.getByRole('button', { name: 'Save configuration', exact: true }).click()
  await navigate(page, 'Document register')
  await page.getByRole('button', { name: 'Register document', exact: true }).click()
  await page.getByRole('button', { name: 'Use a sample document', exact: true }).click()
  await page.getByRole('button', { name: 'Continue', exact: true }).click()
  await expect(
    page.getByLabel('Document class *').locator('option', { hasText: 'Client Charter' }),
  ).toHaveCount(1)
  await page.getByRole('button', { name: 'Close / إغلاق', exact: true }).click()
  await navigate(page, 'Staging & publishing')
  await page.getByRole('button', { name: /Facilities inspection report.*DOC-/ }).click()
  await page.getByRole('button', { name: 'Approval & publishing', exact: true }).click()
  await page.getByRole('button', { name: 'Retry publication', exact: true }).click()
  await expect(page.getByRole('dialog').getByText('Published', { exact: true })).toBeVisible()
  await page.getByRole('button', { name: 'Close', exact: true }).click()
  await page.getByRole('button', { name: 'Notifications', exact: true }).click()
  await page.getByRole('button', { name: 'Mark all read', exact: true }).click()
  await expect(page.getByText('0 unread notifications', { exact: true })).toBeVisible()
  await navigate(page, 'Reports & analytics')
  const reportPromise = page.waitForEvent('download')
  await page.getByRole('button', { name: 'Export CSV', exact: true }).click()
  expect((await reportPromise).suggestedFilename()).toBe('docaya-records-report.csv')
  await navigate(page, 'Audit trail')
  await expect(page.getByText('Promotion replay completed', { exact: true })).toBeVisible()
})

test('desktop, Arabic RTL, mobile and accessible controls', async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 1000 })
  await page.goto('./')
  await page.screenshot({ path: 'test-results/prototype-signin.png', fullPage: true })
  await page.getByRole('button', { name: 'Enter demo workspace', exact: true }).click()
  await page.screenshot({ path: 'test-results/prototype-desktop.png', fullPage: true })
  const results = await new AxeBuilder({ page }).withTags(['wcag2a', 'wcag2aa', 'wcag21aa']).analyze()
  expect(results.violations).toEqual([])
  await page.getByRole('button', { name: 'العربية', exact: true }).click()
  await expect(page.locator('html')).toHaveAttribute('dir', 'rtl')
  await expect(page.getByRole('heading', { name: 'مرحباً بك في دوكايا' })).toBeVisible()
  await page.screenshot({ path: 'test-results/prototype-arabic.png', fullPage: true })
  await page.setViewportSize({ width: 390, height: 844 })
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true)
  await page.getByRole('button', { name: 'فتح التنقل', exact: true }).click()
  await page.locator('nav').getByRole('button', { name: 'البحث واسأل دوكايا', exact: true }).click()
  await expect(page.getByRole('heading', { name: 'الإجابة في وثائقك.' })).toBeVisible()
  await page.screenshot({ path: 'test-results/prototype-mobile-arabic.png', fullPage: true })
})
