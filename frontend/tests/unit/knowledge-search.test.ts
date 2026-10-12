import { describe, expect, it } from 'vitest'
import { discover, normalizeText } from '../../src/prototype/knowledge-search'
import { canSee, seedWorkspace, type RecordItem } from '../../src/prototype/model'

function record(overrides: Partial<RecordItem>): RecordItem {
  return {
    ...seedWorkspace().documents[0],
    title: 'Unrelated title',
    titleAr: '',
    summary: '',
    summaryAr: '',
    reference: '',
    ...overrides,
  }
}

describe('published knowledge discovery', () => {
  it('excludes drafts, archived records and unindexed publications even when the query is empty', () => {
    const approved = record({ id: 'approved', status: 'Published', indexed: true })
    const inputs = [
      approved,
      record({ id: 'draft', status: 'Draft', indexed: true }),
      record({ id: 'archived', status: 'Archived', indexed: true }),
      record({ id: 'unindexed', status: 'Published', indexed: false }),
    ]
    expect(discover(inputs, '').map((r) => r.id)).toEqual(['approved'])
    expect(discover(inputs, 'unrelated').map((r) => r.id)).toEqual(['approved'])
  })
  it('normalises Arabic diacritics and alif variants for bilingual source discovery', () => {
    expect(normalizeText('إِدَارَةُ إلى')).toBe('ادارة الي')
    const arabic = record({ id: 'arabic', titleAr: 'إدارة الوثائق الحكومية' })
    expect(discover([arabic], 'ادارة الوثائق').map((r) => r.id)).toEqual(['arabic'])
  })
  it('ranks a title match ahead of an incidental excerpt without changing caller order', () => {
    const excerpt = record({ id: 'excerpt', summary: 'Review road safety before publication.' })
    const title = record({ id: 'title', title: 'Road safety circular' })
    const inputs = [excerpt, title]
    expect(discover(inputs, 'Find road safety guidance').map((r) => r.id)).toEqual(['title', 'excerpt'])
    expect(inputs.map((r) => r.id)).toEqual(['excerpt', 'title'])
  })
  it('finds a record by tracking number and registered reference', () => {
    const target = record({ id: 'DOC-2026-009001', reference: 'MOI-DEMO-LOOKUP' })
    expect(discover([target], 'DOC-2026-009001')).toEqual([target])
    expect(discover([target], 'MOI-DEMO-LOOKUP')).toEqual([target])
  })
  it('does not invent sources for unmatched, punctuation-only or stop-word-only questions', () => {
    const inputs = [record({})]
    for (const query of ['astronaut', '?!', 'what are the documents', 'ما الوثائق'])
      expect(discover(inputs, query)).toEqual([])
  })
  it('honours the caller’s permission-trimmed source set', () => {
    const state = seedWorkspace()
    const viewerSources = state.documents.filter((r) => canSee(r, 'Viewer', 'Operations'))
    expect(
      discover(state.documents, 'onboarding').some((r) => r.title === 'Employee onboarding checklist'),
    ).toBe(true)
    expect(discover(viewerSources, 'onboarding')).toEqual([])
    expect(
      discover(viewerSources, 'road safety').some(
        (r) => r.title === 'Road safety awareness campaign circular',
      ),
    ).toBe(true)
  })
})
