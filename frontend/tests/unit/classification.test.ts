import { describe, expect, it } from 'vitest'
import { applyClassification, suggestClassification } from '../../src/prototype/classification'
import { seedWorkspace } from '../../src/prototype/model'

const options = {
  classes: [
    'Policy',
    'Procedure',
    'Standard',
    'Contract',
    'Circular',
    'Memo',
    'Report',
    'HR Record',
    'Correspondence',
  ],
  departments: [
    'Operations',
    'Finance',
    'Human Resources',
    'Legal',
    'Civil Defence',
    'Traffic & Patrols',
    'Forensic Sciences',
    'Residency & Identity',
    'Strategy & Governance',
  ],
  defaultDepartment: 'Operations',
}

describe('local registration classification', () => {
  it('uses local TXT content to identify MOI department, class, sensitivity and workflow', () => {
    const result = suggestClassification(
      'scan-001.txt',
      'Forensic Sciences evidence handling standard. Confidential chain of custody records.',
      options,
    )
    expect(result.values).toMatchObject({
      kind: 'Standard',
      department: 'Forensic Sciences',
      sensitivity: 'Confidential',
      flow: 'Sequential',
    })
    expect(result.source).toBe('filename-and-text')
    expect(result.confidence).toBeGreaterThan(80)
    expect(result.reasons.length).toBeGreaterThan(1)
  })
  it('labels filename-only suggestions without implying PDF or OCR extraction', () => {
    const result = suggestClassification('public-traffic-safety-circular.pdf', '', options)
    expect(result.values).toMatchObject({
      title: 'public traffic safety circular',
      kind: 'Circular',
      department: 'Traffic & Patrols',
      sensitivity: 'Public',
      flow: 'Single',
    })
    expect(result.source).toBe('filename')
    expect(result.confidence).toBeLessThan(90)
  })
  it('uses the class stated in the filename before incidental description wording', () => {
    const result = suggestClassification(
      'forensic-evidence-handling-standard.txt',
      'Confidential. This is not an official operational procedure.',
      options,
    )
    expect(result.values.kind).toBe('Standard')
  })
  it('recognises Arabic metadata and routes the strongest sensitivity first', () => {
    const result = suggestClassification('تقرير-أدلة-جنائية.txt', 'سري للغاية. لا ينشر للجمهور.', options)
    expect(result.values).toMatchObject({
      kind: 'Report',
      department: 'Forensic Sciences',
      sensitivity: 'Secret',
      flow: 'Conditional',
    })
  })
  it('leaves unknown classes for human selection and respects available taxonomy', () => {
    const unknown = suggestClassification('scan_001.png', '', options)
    expect(unknown.values).toMatchObject({ kind: '', department: 'Operations', sensitivity: 'Internal' })
    expect(unknown.confidence).toBeLessThan(50)
    const legacy = suggestClassification('civil-defence-procedure.pdf', '', {
      ...options,
      classes: ['Report'],
      departments: ['Operations'],
    })
    expect(legacy.values).toMatchObject({ kind: 'Report', department: 'Operations' })
  })
  it('preserves corrections, original bytes metadata and lifecycle state when applying new suggestions', () => {
    const original = {
      ...seedWorkspace().documents[0],
      title: 'My approved title',
      department: 'Legal',
      sensitivity: 'Secret' as const,
      flow: 'Conditional' as const,
    }
    const before = structuredClone(original)
    const suggestion = suggestClassification(
      'public-traffic-circular.txt',
      'Public road safety circular',
      options,
    )
    const applied = applyClassification(
      original,
      suggestion,
      new Set(['title', 'department', 'sensitivity', 'flow']),
    )
    expect(applied).toMatchObject({
      title: original.title,
      department: 'Legal',
      sensitivity: 'Secret',
      flow: 'Conditional',
      kind: 'Circular',
      hash: original.hash,
      fileName: original.fileName,
      status: original.status,
      indexed: original.indexed,
    })
    expect(original).toEqual(before)
  })
  it('bounds content inspection and omits synthetic header from the description', () => {
    const result = suggestClassification(
      'scan.txt',
      'SYNTHETIC MOI DEMO DOCUMENT\nCivil Defence procedure.\n' + 'x'.repeat(13000) + ' secret',
      options,
    )
    expect(result.values.sensitivity).toBe('Internal')
    expect(result.values.summary).toMatch(/^Civil Defence procedure/)
    expect(result.values.summary.length).toBeLessThanOrEqual(420)
  })
})
