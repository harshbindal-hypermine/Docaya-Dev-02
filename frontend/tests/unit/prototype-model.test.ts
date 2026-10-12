import { describe, expect, it } from 'vitest'
import { approvalSteps, canSee, changeRecord, seedWorkspace } from '../../src/prototype/model'

describe('prototype lifecycle invariants', () => {
  it('keeps the old publication available until its revision is approved, then supersedes it', () => {
    let state = seedWorkspace()
    const original = state.documents[0]
    state = changeRecord(state, original.id, 'Contributor', 'Operations', 'version')
    const draft = state.documents[0]
    expect(draft).toMatchObject({ revises: original.id, version: 1, status: 'Draft', indexed: false })
    expect(state.documents.find((r) => r.id === original.id)?.status).toBe('Published')
    state = changeRecord(state, draft.id, 'Contributor', 'Operations', 'submit')
    state = changeRecord(state, draft.id, 'Approver', 'Operations', 'approve')
    expect(state.documents[0]).toMatchObject({ version: 2, status: 'Published', fileName: original.fileName })
    expect(state.documents.find((r) => r.id === original.id)).toMatchObject({
      status: 'Superseded',
      indexed: false,
    })
  })
  it('requires every sequential approval, preserves the file and publishes only once', () => {
    let state = seedWorkspace()
    const original = state.documents[1]
    expect(() =>
      changeRecord(state, original.id, 'Approver', 'Finance', 'approve', '', 'Compliance officer'),
    ).toThrow('sequence')
    state = changeRecord(state, original.id, 'Approver', 'Finance', 'approve')
    expect(state.documents[1].status).toBe('PendingApproval')
    state = changeRecord(state, original.id, 'Approver', 'Finance', 'approve')
    expect(state.documents[1]).toMatchObject({
      status: 'Published',
      fileName: original.fileName,
      hash: original.hash,
      version: 1,
      indexed: false,
    })
    expect(() => changeRecord(state, original.id, 'Approver', 'Finance', 'approve')).toThrow()
    expect(state.notices[0].recordId).toBe(original.id)
  })
  it('requires return comments and resets approvals on resubmission', () => {
    let state = seedWorkspace()
    const id = state.documents[1].id
    expect(() => changeRecord(state, id, 'Approver', 'Finance', 'return')).toThrow('reason')
    state = changeRecord(state, id, 'Approver', 'Finance', 'return', 'Add cost justification')
    expect(state.documents[1]).toMatchObject({ status: 'Returned', note: 'Add cost justification' })
    state = changeRecord(state, id, 'Contributor', 'Finance', 'submit')
    expect(state.documents[1]).toMatchObject({ status: 'PendingApproval', approvals: [], note: '' })
  })
  it('supports parallel decisions and conditional Secret routing', () => {
    let state = seedWorkspace()
    const parallel = state.documents[11]
    state = changeRecord(state, parallel.id, 'Approver', 'Operations', 'approve', '', 'Compliance officer')
    expect(state.documents[11].status).toBe('PendingApproval')
    state = changeRecord(state, parallel.id, 'Approver', 'Operations', 'approve', '', 'Department head')
    expect(state.documents[11].status).toBe('Published')
    expect(approvalSteps(state.documents[6])).toEqual(['Senior director', 'Compliance officer'])
  })
  it('retains recoverable originals and makes promotion replay idempotent', () => {
    let state = seedWorkspace()
    state.settings.simulateFailure = true
    const id = state.documents[11].id
    state = changeRecord(state, id, 'System Administrator', 'Operations', 'approve')
    state = changeRecord(state, id, 'System Administrator', 'Operations', 'approve')
    expect(state.documents[11]).toMatchObject({ status: 'Approved', staging: 'Active', version: 0 })
    state = changeRecord(state, id, 'System Administrator', 'Operations', 'retry')
    expect(state.documents[11]).toMatchObject({ status: 'Published', version: 1 })
    expect(() => changeRecord(state, id, 'System Administrator', 'Operations', 'retry')).toThrow()
  })
  it('blocks disposition on legal hold and requires release and archive reasons', () => {
    let state = seedWorkspace()
    const id = state.documents[7].id
    expect(() =>
      changeRecord(state, id, 'Records Officer', 'Operations', 'archive', 'Retention due'),
    ).toThrow('blocked')
    expect(() => changeRecord(state, id, 'Records Officer', 'Operations', 'release')).toThrow('reason')
    state = changeRecord(state, id, 'Records Officer', 'Operations', 'release', 'Case closed')
    state = changeRecord(state, id, 'Records Officer', 'Operations', 'archive', 'Approved archive')
    state = changeRecord(state, id, 'Records Officer', 'Operations', 'dispose', 'Retention review approved')
    expect(state.documents[7]).toMatchObject({ status: 'Disposed', indexed: false })
    expect(state.audit[0].detail).toBe('Retention review approved')
  })
  it('trims confidential records and blocks viewer mutations', () => {
    const state = seedWorkspace()
    expect(canSee(state.documents[1], 'Viewer', 'Operations')).toBe(false)
    expect(canSee(state.documents[6], 'Contributor', 'Legal')).toBe(false)
    expect(canSee(state.documents[0], 'Viewer', 'Operations')).toBe(true)
    expect(() => changeRecord(state, state.documents[0].id, 'Viewer', 'Operations', 'hold', 'Test')).toThrow()
    expect(() => changeRecord(state, state.documents[1].id, 'Approver', 'Operations', 'approve')).toThrow(
      'Access denied',
    )
  })
})
