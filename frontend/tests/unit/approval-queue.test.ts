import { describe, expect, it } from 'vitest'
import { approvalQueue } from '../../src/prototype/approval-queue'
import { seedWorkspace, type RecordItem } from '../../src/prototype/model'

describe('approval inbox ordering and filters', () => {
  const record = (id: string, due: string, status: RecordItem['status'] = 'PendingApproval'): RecordItem => ({
    ...seedWorkspace().documents[0],
    id,
    due,
    status,
  })
  it('keeps decisions separate from returned/publication work, orders dates and puts undated items last', () => {
    const rows = [
      record('late', '2026-09-09'),
      record('undated', ''),
      record('returned', '2026-09-01', 'Returned'),
      record('publish-retry', '2026-09-01', 'Approved'),
      record('early-b', '2026-09-02'),
      record('invalid', 'invalid'),
      record('early-a', '2026-09-02'),
    ]
    const original = rows.map((item) => item.id)
    expect(approvalQueue(rows, 'pending').map((item) => item.id)).toEqual([
      'early-a',
      'early-b',
      'late',
      'invalid',
      'undated',
    ])
    expect(approvalQueue(rows, 'returned').map((item) => item.id)).toEqual(['returned'])
    expect(rows.map((item) => item.id)).toEqual(original)
  })
  it('combines normalized Arabic search with due filtering and excludes a completed item', () => {
    const now = Date.parse('2026-09-06T12:00:00Z')
    const rows = [
      { ...record('overdue', '2026-09-06T11:00:00Z'), titleAr: 'إجراءات الأدلة' },
      { ...record('later', '2026-09-07'), titleAr: 'إجراءات الأدلة' },
      { ...record('unrelated', '2026-09-01'), titleAr: 'سلامة المرور' },
    ]
    expect(approvalQueue(rows, 'pending', 'اجراءات الادلة', true, now).map((item) => item.id)).toEqual([
      'overdue',
    ])
    rows[0].status = 'Published'
    expect(approvalQueue(rows, 'pending', 'اجراءات الادلة', true, now)).toEqual([])
    expect(approvalQueue(rows, 'pending', 'اجراءات الادلة', false, now).map((item) => item.id)).toEqual([
      'later',
    ])
  })
})
