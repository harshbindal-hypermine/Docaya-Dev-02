import { describe, expect, it } from 'vitest'
import { migrateWorkspace, seedWorkspace, SEED_VERSION } from '../../src/prototype/model'

describe('synthetic UAE workshop fixtures', () => {
  it('preserves legacy fixture positions and adds bilingual ministry records with valid lifecycle dates', () => {
    const state = seedWorkspace()
    expect(state.seedVersion).toBe(SEED_VERSION)
    expect(state.documents[1]).toMatchObject({
      id: 'DOC-2026-000113',
      title: 'Supplier framework agreement',
      status: 'PendingApproval',
      department: 'Finance',
    })
    expect(state.documents[11].title).toBe('Interdepartmental service charter')
    const samples = state.documents.filter((record) => record.sampleKey)
    expect(samples).toHaveLength(12)
    expect(new Set(state.documents.map((record) => record.id)).size).toBe(state.documents.length)
    expect(samples.filter((record) => record.status === 'PendingApproval')).toHaveLength(5)
    for (const record of samples) {
      expect(record.summary).toContain('Synthetic')
      expect(record.summaryAr).toMatch(/[\u0600-\u06ff]/)
      expect(Date.parse(record.captured)).toBeLessThan(Date.parse(record.expiry))
      expect(Date.parse(record.captured)).toBeLessThan(Date.parse(record.due))
    }
  })

  it('adds missing samples once while preserving uploaded files, edited records, settings and feedback', () => {
    const legacy = seedWorkspace()
    delete legacy.seedVersion
    legacy.documents = legacy.documents.slice(0, 12)
    legacy.documents[0] = { ...legacy.documents[0], title: 'Client-edited policy', status: 'Archived' }
    // An earlier user upload may already own a newly reserved fixture number.
    const upload = {
      ...legacy.documents[0],
      id: 'DOC-2026-000201',
      title: 'Client upload',
      hash: 'original-file-hash',
    }
    legacy.documents.push(upload)
    legacy.settings.classes = ['Client-specific type']
    legacy.settings.sla = 96
    legacy.feedback = [
      { id: 'feedback-1', module: 'Approvals', note: 'Keep my notes', priority: 'Must have' },
    ]
    const migrated = migrateWorkspace(legacy)
    expect(migrated.documents.slice(0, 13)).toEqual(legacy.documents)
    expect(migrated.documents).toHaveLength(24)
    expect(migrated.documents.find((record) => record.id === upload.id)).toEqual(upload)
    expect(migrated.settings.classes).toContain('Client-specific type')
    expect(migrated.settings.classes).toContain('Procedure')
    expect(migrated.settings.sla).toBe(96)
    expect(migrated.feedback).toEqual(legacy.feedback)
    expect(migrated.audit).toEqual(legacy.audit)
    expect(migrateWorkspace(migrated)).toBe(migrated)
    migrated.documents = migrated.documents.filter((record) => !record.sampleKey)
    expect(migrateWorkspace(migrated).documents).toHaveLength(13)
  })
})
