import type { RecordItem } from './model'
import { normalizeText } from './knowledge-search'

export type ApprovalView = 'pending' | 'returned'

export function approvalQueue(
  rows: RecordItem[],
  view: ApprovalView,
  query = '',
  overdueOnly = false,
  now = Date.now(),
) {
  const needle = normalizeText(query)
  const dueTime = (record: RecordItem) => {
    const time = Date.parse(record.due)
    return Number.isFinite(time) ? time : Infinity
  }
  return rows
    .filter(
      (record) =>
        record.status === (view === 'pending' ? 'PendingApproval' : 'Returned') &&
        (!overdueOnly || view !== 'pending' || dueTime(record) < now) &&
        normalizeText(`${record.title} ${record.titleAr} ${record.id} ${record.department}`).includes(needle),
    )
    .sort((a, b) => dueTime(a) - dueTime(b) || a.id.localeCompare(b.id))
}
