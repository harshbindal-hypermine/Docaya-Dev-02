import { ArrowRight, CheckCheck, FileText, Search, X } from 'lucide-react'
import type { Language, RecordItem } from './model'
import type { ApprovalView } from './approval-queue'
import type { Translate } from './ui'
import { local } from './translations'

export function ApprovalQueue({
  rows,
  pendingCount,
  returnedCount,
  selectedId,
  onOpen,
  lang,
  t,
  query,
  onQuery,
  view,
  onView,
  overdueOnly,
  onOverdue,
}: {
  rows: RecordItem[]
  pendingCount: number
  returnedCount: number
  selectedId: string
  onOpen: (record: RecordItem) => void
  lang: Language
  t: Translate
  query: string
  onQuery: (query: string) => void
  view: ApprovalView
  onView: (view: ApprovalView) => void
  overdueOnly: boolean
  onOverdue: (value: boolean) => void
}) {
  const filtered = !!query.trim() || overdueOnly
  const dateLabel = (record: RecordItem) => {
    const due = Date.parse(record.due)
    if (!Number.isFinite(due)) return t('No due date', 'دون موعد محدد')
    const date = new Date(due).toLocaleDateString(lang === 'ar' ? 'ar-AE' : 'en-GB', {
      day: 'numeric',
      month: 'short',
      year: 'numeric',
    })
    return `${view === 'pending' && due < Date.now() ? t('Overdue', 'متأخر') : t('Due', 'الموعد')} · ${date}`
  }
  return (
    <section
      className={`d-approval-workspace d-simple-queue ${selectedId ? 'reviewing' : ''}`}
      aria-label={t('Approval workspace', 'مساحة الاعتماد')}
    >
      <div className="d-queue-panel">
        <header className="d-inbox-heading">
          <div>
            <h2>
              {view === 'pending'
                ? t(`${pendingCount} documents to review`, `${pendingCount} وثائق للمراجعة`)
                : t(`${returnedCount} returned for changes`, `${returnedCount} وثائق معادة للتعديل`)}
            </h2>
            <p>
              {view === 'pending'
                ? t(
                    'Open a document, review it, then make your decision.',
                    'افتح الوثيقة وراجعها ثم اتخذ قرارك.',
                  )
                : t('Waiting for the document owner to make changes.', 'بانتظار تعديل الوثيقة من مالكها.')}
            </p>
          </div>
          {view === 'pending' && rows[0] && (
            <button className="p-btn primary" onClick={() => onOpen(rows[0])}>
              {t('Review next', 'مراجعة التالية')}
              <ArrowRight size={16} />
            </button>
          )}
        </header>
        <div className="d-inbox-toolbar">
          <div className="d-queue-filters" role="group" aria-label={t('Queue view', 'عرض القائمة')}>
            <button aria-pressed={view === 'pending'} onClick={() => onView('pending')}>
              {t('To review', 'للمراجعة')} <span>{pendingCount}</span>
            </button>
            <button aria-pressed={view === 'returned'} onClick={() => onView('returned')}>
              {t('Returned', 'معادة')} <span>{returnedCount}</span>
            </button>
          </div>
          <div className="d-queue-search">
            <Search size={16} aria-hidden="true" />
            <input
              value={query}
              onChange={(event) => onQuery(event.target.value)}
              aria-label={t('Search approval queue', 'بحث قائمة الاعتماد')}
              placeholder={t('Search documents…', 'ابحث عن وثيقة…')}
            />
            {query && (
              <button
                className="p-icon"
                aria-label={t('Clear queue search', 'مسح بحث القائمة')}
                onClick={() => onQuery('')}
              >
                <X size={15} />
              </button>
            )}
          </div>
        </div>
        <div className="d-inbox-order">
          <span>
            {view === 'pending'
              ? t('Earliest due first', 'الأقرب موعداً أولاً')
              : t('Awaiting changes', 'بانتظار التعديل')}
          </span>
          {view === 'pending' && (
            <label>
              <input
                type="checkbox"
                checked={overdueOnly}
                onChange={(event) => onOverdue(event.target.checked)}
              />
              {t('Overdue only', 'المتأخرة فقط')}
            </label>
          )}
        </div>
        <div className="d-inbox-columns" aria-hidden="true">
          <span>{t('Document', 'الوثيقة')}</span>
          <span>{t('Department', 'الإدارة')}</span>
          <span>{view === 'pending' ? t('Review due', 'موعد المراجعة') : t('Status', 'الحالة')}</span>
          <span />
        </div>
        <div className="d-queue-list" aria-label={t('Documents in this queue', 'وثائق هذه القائمة')}>
          {rows.map((record) => (
            <button
              className={`d-review-item d-inbox-row ${selectedId === record.id ? 'selected' : ''}`}
              aria-current={selectedId === record.id ? 'true' : undefined}
              key={record.id}
              onClick={() => onOpen(record)}
            >
              <span className="d-inbox-document">
                <span className="d-inbox-file">
                  <FileText size={20} aria-hidden="true" />
                </span>
                <span>
                  <strong>{lang === 'ar' ? record.titleAr || record.title : record.title}</strong>
                  <small dir="ltr">{record.id}</small>
                </span>
              </span>
              <span className="d-inbox-department">{local(record.department, lang)}</span>
              <span
                className={`d-inbox-due ${view === 'pending' && Date.parse(record.due) < Date.now() ? 'overdue' : ''}`}
              >
                {view === 'pending' ? dateLabel(record) : t('Awaiting changes', 'بانتظار التعديل')}
              </span>
              <span className="d-inbox-open">
                {selectedId === record.id
                  ? t('Reviewing', 'قيد المراجعة')
                  : view === 'pending'
                    ? t('Review', 'مراجعة')
                    : t('View', 'عرض')}
                <ArrowRight size={16} aria-hidden="true" />
              </span>
            </button>
          ))}
          {!rows.length && (
            <div className="d-inbox-empty" role="status">
              {filtered ? <Search size={28} /> : <CheckCheck size={30} />}
              <h3>
                {filtered
                  ? t('No matching documents', 'لا توجد وثائق مطابقة')
                  : view === 'pending'
                    ? t('All caught up', 'اكتملت جميع المراجعات')
                    : t('No returned documents', 'لا توجد وثائق معادة')}
              </h3>
              <p>
                {filtered
                  ? t('Try another search or clear your filters.', 'جرّب بحثاً آخر أو امسح المرشحات.')
                  : view === 'pending'
                    ? t('There are no documents awaiting approval.', 'لا توجد وثائق بانتظار الاعتماد.')
                    : t(
                        'Documents returned for changes will appear here.',
                        'ستظهر هنا الوثائق المعادة للتعديل.',
                      )}
              </p>
              {filtered && (
                <button
                  className="p-btn"
                  onClick={() => {
                    onQuery('')
                    onOverdue(false)
                  }}
                >
                  {t('Clear filters', 'مسح المرشحات')}
                </button>
              )}
            </div>
          )}
        </div>
      </div>
    </section>
  )
}
