import { test, expect, type Page } from '@playwright/test'
import AxeBuilder from '@axe-core/playwright'
import { readFile } from 'node:fs/promises'
import { createHash } from 'node:crypto'
import type { Workspace } from '../../src/prototype/model'

async function enter(page: Page) {
  await page.goto('./')
  await page.getByRole('button', { name: 'Enter demo workspace', exact: true }).click()
}
async function navigate(page: Page, name: string) {
  await page
    .locator('nav')
    .getByRole('button', { name: new RegExp(`^${name}(?: \\d+)?$`) })
    .click()
}
async function expectNoBlur(page: Page) {
  expect(
    await page.evaluate(() =>
      [...document.querySelectorAll('.p-overlay, .d-review-drawer, .p-content')].every((node) => {
        const style = getComputedStyle(node)
        return !style.backdropFilter.includes('blur') && !style.filter.includes('blur')
      }),
    ),
  ).toBe(true)
}
async function workspace(page: Page): Promise<Workspace> {
  return page.evaluate(() => JSON.parse(localStorage.getItem('docaya-prototype-v1')!))
}

test('automatic intake keeps overrides and original bytes, requires confirmation, and catches duplicates', async ({
  page,
}) => {
  await page.setViewportSize({ width: 1600, height: 1000 })
  await enter(page)
  await page.getByRole('button', { name: 'Register document', exact: true }).click()
  const intake = page.getByRole('dialog', { name: 'Register a document', exact: true })
  await expect(intake).toHaveAttribute('aria-modal', 'false')
  await expectNoBlur(page)
  await intake.getByLabel('Choose file', { exact: true }).setInputFiles({
    name: 'forensic-evidence-standard.txt',
    mimeType: 'text/plain',
    buffer: Buffer.from('Forensic Sciences evidence handling standard. Confidential workshop content.'),
  })
  await expect(intake.getByText('Docaya has prepared your metadata')).toBeVisible()
  await intake.getByRole('button', { name: 'Continue', exact: true }).click()
  await expect(intake.getByLabel('Document class *')).toHaveValue('Standard')
  await expect(intake.getByLabel('Owning department *')).toHaveValue('Forensic Sciences')
  await expect(intake.getByLabel('Sensitivity *')).toHaveValue('Confidential')
  await expect(intake.getByLabel('Approval flow *')).toHaveValue('Sequential')
  await intake.getByLabel('Business title *', { exact: true }).fill('Reviewer intake corrections')
  await intake.getByLabel('Owning department *').selectOption('Operations')
  await intake.getByLabel('Sensitivity *').selectOption('Public')
  await intake.getByLabel('Approval flow *').selectOption('Single')
  await intake.getByRole('button', { name: 'Back', exact: true }).click()
  const content =
    'SYNTHETIC CLIENT FILE\nCivil Defence evacuation procedure.\nThe bytes, punctuation & Arabic العربية stay unchanged.\n'
  await intake.getByLabel('Choose file', { exact: true }).setInputFiles({
    name: 'civil-defence-evacuation-procedure.txt',
    mimeType: 'text/plain',
    buffer: Buffer.from(content),
  })
  await expect(intake.locator('.d-original-text pre')).toHaveText(content)
  await intake.getByRole('button', { name: 'Continue', exact: true }).click()
  await expect(intake.getByLabel('Business title *', { exact: true })).toHaveValue(
    'Reviewer intake corrections',
  )
  await expect(intake.getByLabel('Owning department *')).toHaveValue('Operations')
  await expect(intake.getByLabel('Sensitivity *')).toHaveValue('Public')
  await expect(intake.getByLabel('Approval flow *')).toHaveValue('Single')
  await expect(intake.getByLabel('Document class *')).toHaveValue('Procedure')
  await expect(intake.getByText('Your value', { exact: true })).toHaveCount(2)
  await intake.getByRole('button', { name: 'Continue', exact: true }).click()
  await expect(intake.getByRole('button', { name: 'Submit for approval', exact: true })).toBeDisabled()
  await intake.getByRole('checkbox', { name: /I have reviewed the document and classification/ }).check()
  await intake.getByRole('button', { name: 'Back', exact: true }).click()
  await intake.getByLabel('Business title *', { exact: true }).fill('Reviewer final intake decision')
  await intake.getByRole('button', { name: 'Continue', exact: true }).click()
  await expect(intake.getByRole('checkbox')).not.toBeChecked()
  await expect(intake.getByRole('button', { name: 'Submit for approval', exact: true })).toBeDisabled()
  await expect(intake.locator('.p-hash')).toHaveText(createHash('sha256').update(content).digest('hex'))
  await intake.getByRole('checkbox').check()
  await intake.getByRole('button', { name: 'Submit for approval', exact: true }).click()
  await page
    .locator('.d-queue-list')
    .getByRole('button', { name: /Reviewer final intake decision/ })
    .click()
  const review = page.getByRole('dialog', { name: 'Reviewer final intake decision', exact: true })
  await expect(review.locator('.d-original-text pre')).toHaveText(content)
  await review.getByRole('button', { name: 'Details', exact: true }).click()
  const downloadPromise = page.waitForEvent('download')
  await review.getByRole('button', { name: 'Download original / sample', exact: true }).click()
  const download = await downloadPromise
  expect(download.suggestedFilename()).toBe('civil-defence-evacuation-procedure.txt')
  expect(await readFile((await download.path())!, 'utf8')).toBe(content)
  await page.keyboard.press('Escape')
  await navigate(page, 'Document register')
  await page.getByRole('button', { name: 'Register document', exact: true }).click()
  await page
    .getByLabel('Choose file', { exact: true })
    .setInputFiles({ name: 'renamed-duplicate.txt', mimeType: 'text/plain', buffer: Buffer.from(content) })
  await expect(page.getByRole('alert')).toContainText('This file is already registered')
  await expect(page.getByRole('button', { name: 'Continue', exact: true })).toBeDisabled()
})

test('approval drawer keeps the queue operable and preview beside every details tab', async ({ page }) => {
  await page.setViewportSize({ width: 1600, height: 1000 })
  await enter(page)
  await navigate(page, 'Approvals')
  const queue = page.locator('.d-queue-list')
  const first = queue.getByRole('button', { name: /Civil Defence readiness review/ })
  await first.click()
  let drawer = page.getByRole('dialog', { name: 'Civil Defence readiness review', exact: true })
  await expect(drawer).toHaveAttribute('aria-modal', 'false')
  await expect(first).toHaveAttribute('aria-current', 'true')
  await expectNoBlur(page)
  await expect(drawer.locator('.d-review-tabs button')).toHaveCount(3)
  for (const name of ['Review', 'Details', 'Activity']) {
    await drawer.getByRole('button', { name, exact: true }).click()
    await expect(drawer.locator('.d-review-preview')).toBeVisible()
    await expect(drawer.locator('.d-document-paper h3')).toHaveText('Civil Defence readiness review')
    const preview = await drawer.locator('.d-review-preview').boundingBox()
    const inspector = await drawer.locator('.d-review-inspector').boundingBox()
    expect(preview!.x + preview!.width).toBeLessThanOrEqual(inspector!.x + 2)
  }
  await queue.getByRole('button', { name: /Evidence custody documentation procedure/ }).click()
  drawer = page.getByRole('dialog', { name: 'Evidence custody documentation procedure', exact: true })
  await expect(drawer.locator('.d-document-paper h3')).toHaveText('Evidence custody documentation procedure')
  await expect(
    queue.getByRole('button', { name: /Evidence custody documentation procedure/ }),
  ).toHaveAttribute('aria-current', 'true')
  await drawer.getByRole('button', { name: 'Next document', exact: true }).click()
  await expect(page.locator('.d-review-drawer')).toBeVisible()
  await expect(page.locator('.d-review-drawer')).not.toHaveAttribute(
    'aria-label',
    'Evidence custody documentation procedure',
  )
  await expect(page.locator('.d-review-preview')).toBeVisible()
  await page.keyboard.press('Escape')
  await expect(page.locator('.d-review-drawer')).toHaveCount(0)
  await expect(queue).toBeVisible()
})

test('approval inbox shows pending work by due date, preserves filtered navigation and separates returns', async ({
  page,
}) => {
  await page.setViewportSize({ width: 1600, height: 1000 })
  await enter(page)
  await navigate(page, 'Approvals')
  const initial = await workspace(page)
  const pending = initial.documents.filter((record) => record.status === 'PendingApproval')
  const returnedCount = initial.documents.filter((record) => record.status === 'Returned').length
  const queue = page.locator('.d-queue-list')
  const rows = queue.getByRole('button')
  const views = page.getByRole('group', { name: 'Queue view', exact: true })
  await expect(
    views.getByRole('button', { name: `To review ${pending.length}`, exact: true }),
  ).toHaveAttribute('aria-pressed', 'true')
  await expect(rows).toHaveCount(pending.length)
  await expect(
    page.getByRole('heading', { name: `${pending.length} documents to review`, exact: true }),
  ).toBeVisible()
  const ids = await rows.locator('.d-inbox-document small').allTextContents()
  expect(new Set(ids)).toEqual(new Set(pending.map((record) => record.id)))
  const dueDates = ids.map((id) => Date.parse(pending.find((record) => record.id === id)!.due))
  expect(dueDates).toEqual([...dueDates].sort((a, b) => a - b))
  await expect(page.getByText('Earliest due first', { exact: true })).toBeVisible()

  const search = page.getByRole('textbox', { name: 'Search approval queue', exact: true })
  await search.fill('service')
  const matches = pending.filter((record) =>
    `${record.title} ${record.titleAr} ${record.id} ${record.department}`.toLowerCase().includes('service'),
  )
  expect(matches.length).toBeGreaterThan(1)
  await expect(rows).toHaveCount(matches.length)
  const matchingIds = await rows.locator('.d-inbox-document small').allTextContents()
  await rows.first().click()
  let drawer = page.locator('.d-review-drawer')
  await expect(drawer.locator('.d-review-navigation')).toContainText(`1 / ${matches.length}`)
  await drawer.getByRole('button', { name: 'Next document', exact: true }).click()
  await expect(drawer.locator('.d-review-meta')).toContainText(matchingIds[1])
  await expect(rows.nth(1)).toHaveAttribute('aria-current', 'true')
  await drawer.getByRole('button', { name: 'Close review drawer', exact: true }).click()
  await expect(search).toHaveValue('service')
  await search.fill('no-document-can-match-this-query')
  await expect(queue.getByRole('heading', { name: 'No matching documents', exact: true })).toBeVisible()
  await queue.getByRole('button', { name: 'Clear filters', exact: true }).click()
  await expect(rows).toHaveCount(pending.length)

  const returnedId = await rows.first().locator('.d-inbox-document small').innerText()
  await rows.first().click()
  drawer = page.locator('.d-review-drawer')
  await drawer.getByRole('button', { name: 'Return for changes', exact: true }).click()
  const reason = drawer.getByRole('textbox', { name: 'What needs to change? (required)', exact: true })
  await expect(reason).toBeFocused()
  await drawer.getByRole('button', { name: 'Confirm return', exact: true }).click()
  await expect(drawer.getByRole('alert')).toHaveText(
    'Explain what needs to change before returning the document.',
  )
  await expect(reason).toBeFocused()
  expect((await workspace(page)).documents.find((record) => record.id === returnedId)?.status).toBe(
    'PendingApproval',
  )
  await reason.fill('Please clarify the accountable owner and review deadline.')
  await drawer.getByRole('button', { name: 'Confirm return', exact: true }).click()
  await expect(drawer.getByRole('status')).toContainText('Returned for changes')
  await expect(drawer.getByRole('button', { name: 'Approve & sign', exact: true })).toHaveCount(0)
  await expect(rows.filter({ hasText: returnedId })).toHaveCount(0)
  await expect(rows).toHaveCount(pending.length - 1)
  await drawer.getByRole('button', { name: 'Close review drawer', exact: true }).click()
  await views.getByRole('button', { name: `Returned ${returnedCount + 1}`, exact: true }).click()
  await expect(rows).toHaveCount(returnedCount + 1)
  await rows.filter({ hasText: returnedId }).click()
  await expect(
    drawer.getByText('Please clarify the accountable owner and review deadline.', { exact: true }),
  ).toBeVisible()
  await expect(drawer.getByRole('button', { name: 'Approve & sign', exact: true })).toHaveCount(0)
})

test('parallel approval saves one selected step and requires explicit continuation before the remaining decision', async ({
  page,
}) => {
  await page.setViewportSize({ width: 1600, height: 1000 })
  await enter(page)
  await navigate(page, 'Approvals')
  const initial = await workspace(page)
  const parallel = initial.documents.find(
    (record) => record.status === 'PendingApproval' && record.flow === 'Parallel' && !record.approvals.length,
  )!
  expect(parallel).toBeTruthy()
  const queue = page.locator('.d-queue-list')
  const row = queue.getByRole('button').filter({ hasText: parallel.id })
  const count = await queue.getByRole('button').count()
  await row.click()
  const drawer = page.getByRole('dialog', { name: parallel.title, exact: true })
  const reviewingAs = drawer.getByRole('combobox', { name: 'Reviewing as', exact: true })
  await reviewingAs.selectOption('Compliance officer')
  await expect(drawer.getByRole('button', { name: 'Approve & sign', exact: true })).toHaveCount(1)
  await drawer.getByRole('button', { name: 'Approve & sign', exact: true }).click()
  await expect(drawer.getByRole('status')).toContainText('Another review step is still required.')
  await expect(drawer.getByRole('status')).toBeFocused()
  await expect(row).toHaveAttribute('aria-current', 'true')
  await expect(queue.getByRole('button')).toHaveCount(count)
  await expect(drawer.getByRole('button', { name: 'Approve & sign', exact: true })).toHaveCount(0)
  const partial = (await workspace(page)).documents.find((record) => record.id === parallel.id)!
  expect(partial.status).toBe('PendingApproval')
  expect(partial.approvals).toEqual(['Compliance officer'])
  await drawer.getByRole('button', { name: 'Review the remaining step', exact: true }).click()
  await expect(drawer.locator('.d-decision-as')).toContainText('Department head')
  await drawer.getByRole('button', { name: 'Approve & sign', exact: true }).click()
  await expect(drawer.getByRole('status')).toContainText(
    'All review steps are complete. The document is published.',
  )
  await expect(row).toHaveCount(0)
  await expect(queue.getByRole('button')).toHaveCount(count - 1)
  await expect(drawer.getByRole('button', { name: 'Review the remaining step', exact: true })).toHaveCount(0)
  await drawer.getByRole('button', { name: 'Next pending document', exact: true }).click()
  await expect(page.locator('.d-review-drawer')).not.toHaveAttribute('aria-label', parallel.title)
  await expect(
    page.locator('.d-review-drawer').getByRole('button', { name: 'Approve & sign', exact: true }),
  ).toBeVisible()
})

test('Arabic mobile approval controls are accessible, visible and require a focused return reason', async ({
  page,
}) => {
  await enter(page)
  await navigate(page, 'Approvals')
  await page.getByRole('button', { name: 'العربية', exact: true }).click()
  await page.setViewportSize({ width: 390, height: 844 })
  await expect(page.locator('html')).toHaveAttribute('dir', 'rtl')
  const queue = page.locator('.d-queue-list')
  const first = queue.getByRole('button').first()
  await first.click()
  const drawer = page.locator('.d-review-drawer')
  await expect(drawer).toHaveAttribute('aria-modal', 'false')
  await expectNoBlur(page)
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true)
  const approve = drawer.getByRole('button', { name: 'اعتماد وتوقيع', exact: true })
  const returnDocument = drawer.getByRole('button', { name: 'إرجاع للتعديل', exact: true })
  await expect(approve).toBeInViewport({ ratio: 1 })
  await expect(returnDocument).toBeInViewport({ ratio: 1 })
  await approve.click({ trial: true })
  const previewHeight = (await drawer.locator('.d-review-preview').boundingBox())!.height
  await drawer.getByRole('button', { name: 'توسيع المعاينة', exact: true }).click()
  expect((await drawer.locator('.d-review-preview').boundingBox())!.height).toBeGreaterThan(previewHeight)
  await expect(approve).toBeInViewport({ ratio: 1 })
  await expect(returnDocument).toBeInViewport({ ratio: 1 })
  await drawer.getByRole('button', { name: 'العودة إلى المراجعة', exact: true }).click()
  const accessibility = await new AxeBuilder({ page })
    .include('.d-review-drawer')
    .withTags(['wcag2a', 'wcag2aa', 'wcag21aa'])
    .analyze()
  expect(accessibility.violations).toEqual([])
  await returnDocument.click()
  const reason = drawer.getByRole('textbox', { name: 'ما التعديلات المطلوبة؟ (إلزامي)', exact: true })
  await expect(reason).toBeFocused()
  await expect(reason).toBeInViewport({ ratio: 1 })
  const confirm = drawer.getByRole('button', { name: 'تأكيد الإرجاع', exact: true })
  await expect(confirm).toBeInViewport({ ratio: 1 })
  await confirm.click()
  await expect(drawer.getByRole('alert')).toHaveText('وضح التعديلات المطلوبة قبل إرجاع الوثيقة.')
  await expect(reason).toBeFocused()
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true)
  await drawer.getByRole('button', { name: 'إلغاء', exact: true }).click()
  await drawer.getByRole('button', { name: 'إغلاق درج المراجعة', exact: true }).click()
  await expect(first).toBeFocused()
  await expect(queue).toBeVisible()
})

test('thumbnail and list search share results and cited answers open their document', async ({ page }) => {
  await enter(page)
  await navigate(page, 'Search & Ask Docaya')
  await expect(page.getByRole('button', { name: 'Thumbnail view', exact: true })).toHaveAttribute(
    'aria-pressed',
    'true',
  )
  await page.getByRole('textbox', { name: 'Search published records', exact: true }).fill('road safety')
  const cards = page.locator('.d-thumbnail-grid > .d-source-card')
  await expect(cards.first()).toBeVisible()
  const count = await cards.count()
  await page.getByRole('button', { name: 'List view', exact: true }).click()
  await expect(page.locator('tbody tr')).toHaveCount(count)
  await page.getByRole('button', { name: 'Thumbnail view', exact: true }).click()
  await expect(cards).toHaveCount(count)
  await page.getByRole('textbox', { name: 'Ask Docaya question', exact: true }).fill('road safety awareness')
  await page.getByRole('button', { name: 'Ask Docaya', exact: true }).click()
  await page.locator('.p-citation').filter({ hasText: 'Road safety awareness campaign circular' }).click()
  await expect(
    page.getByRole('dialog', { name: 'Road safety awareness campaign circular', exact: true }),
  ).toBeVisible()
  await page.keyboard.press('Escape')
  await expect(page.getByRole('textbox', { name: 'Search published records', exact: true })).toHaveValue(
    'road safety',
  )
})

test('assistant cites sources and removes previously visible protected answers after persona changes', async ({
  page,
}) => {
  await enter(page)
  const launcher = page.getByRole('button', { name: 'Open Docaya AI Assistant', exact: true })
  await launcher.click()
  const assistant = page.getByRole('dialog', { name: 'Docaya AI Assistant', exact: true })
  await expect(assistant).toHaveAttribute('aria-modal', 'false')
  await assistant.getByRole('textbox', { name: 'Message Docaya assistant', exact: true }).fill('onboarding')
  await assistant.getByRole('button', { name: 'Send question', exact: true }).click()
  await expect(
    assistant.getByRole('button', { name: 'Preview Employee onboarding checklist', exact: true }),
  ).toBeVisible()
  await page.getByRole('combobox', { name: 'Demo persona', exact: true }).selectOption('Viewer')
  await expect(
    assistant.getByRole('button', { name: 'Preview Employee onboarding checklist', exact: true }),
  ).toHaveCount(0)
  await expect(
    assistant.getByText(
      'Onboarding checklist covering induction, access provisioning and mandatory training.',
      { exact: true },
    ),
  ).toHaveCount(0)
  await expect(assistant.getByText(/I could not find a supporting published source/)).toBeVisible()
  await assistant.getByRole('textbox', { name: 'Message Docaya assistant', exact: true }).fill('road safety')
  await assistant.getByRole('button', { name: 'Send question', exact: true }).click()
  await expect(
    assistant.getByRole('button', { name: 'Preview Road safety awareness campaign circular', exact: true }),
  ).toBeVisible()
  await assistant.getByRole('button', { name: 'Helpful answer', exact: true }).last().click()
  await expect(assistant.getByRole('button', { name: 'Helpful answer', exact: true }).last()).toHaveAttribute(
    'aria-pressed',
    'true',
  )
  await assistant.getByRole('textbox', { name: 'Message Docaya assistant', exact: true }).press('Escape')
  await expect(assistant).toHaveCount(0)
  await expect(launcher).toBeFocused()
})

test('Arabic mobile discovery, assistant and intake remain within a 390px viewport', async ({ page }) => {
  await enter(page)
  await page.getByRole('button', { name: 'العربية', exact: true }).click()
  await page.setViewportSize({ width: 390, height: 844 })
  await expect(page.locator('html')).toHaveAttribute('dir', 'rtl')
  await page.getByRole('button', { name: 'فتح التنقل', exact: true }).click()
  await navigate(page, 'البحث واسأل دوكايا')
  await expect(page.getByRole('heading', { name: 'الإجابة في وثائقك.', exact: true })).toBeVisible()
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true)
  await page.getByRole('button', { name: 'فتح مساعد دوكايا الذكي', exact: true }).click()
  await expect(page.getByRole('dialog', { name: 'مساعد دوكايا الذكي', exact: true })).toBeVisible()
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true)
  await page.getByRole('button', { name: 'تصغير المساعد', exact: true }).click()
  await page.getByRole('button', { name: 'فتح التنقل', exact: true }).click()
  await navigate(page, 'سجل الوثائق')
  await page.getByRole('button', { name: 'تسجيل وثيقة', exact: true }).click()
  const intake = page.getByRole('dialog', { name: 'تسجيل وثيقة', exact: true })
  await intake.getByRole('button', { name: 'استخدام وثيقة تجريبية', exact: true }).click()
  await expect(intake.getByText('أعد دوكايا البيانات الوصفية', { exact: true })).toBeVisible()
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true)
  await expectNoBlur(page)
  await page.screenshot({ path: 'test-results/experience-arabic-intake-mobile.png', fullPage: true })
})
