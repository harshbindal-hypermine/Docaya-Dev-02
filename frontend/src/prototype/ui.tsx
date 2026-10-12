import { local } from './translations'
import { useCallback, type ReactNode } from 'react'
import { X, FileText, ChevronRight } from 'lucide-react'
import { useDialogFocus } from '../hooks/useDialogFocus'
import type { Language, RecordItem } from './model'
export type Translate = (en: string, ar: string) => string
export function Badge({ value, lang }: { value: string; lang: Language }) {
  return <span className={`p-badge ${value.toLowerCase().replaceAll(' ', '-')}`}>{local(value, lang)}</span>
}
export function Modal({
  title,
  onClose,
  children,
  wide = false,
  variant = 'modal',
}: {
  title: string
  onClose: () => void
  children: ReactNode
  wide?: boolean
  variant?: 'modal' | 'drawer'
}) {
  const close = useCallback(onClose, [onClose])
  const ref = useDialogFocus(close, variant !== 'drawer')
  return (
    <div
      className={`p-overlay ${variant === 'drawer' ? 'p-drawer-overlay' : ''}`}
      onMouseDown={(e) => {
        if (e.target === e.currentTarget) onClose()
      }}
    >
      <section
        ref={ref}
        className={`p-modal ${wide ? 'wide' : ''}`}
        role="dialog"
        aria-modal={variant !== 'drawer'}
        aria-label={title}
      >
        <header>
          <h2>{title}</h2>
          <button className="p-icon" aria-label="Close / إغلاق" onClick={onClose}>
            <X size={20} />
          </button>
        </header>
        {children}
      </section>
    </div>
  )
}
export function Field({ label, children }: { label: string; children: ReactNode }) {
  return (
    <label className="p-field">
      <span>{label}</span>
      {children}
    </label>
  )
}
export function Empty({ t }: { t: Translate }) {
  return (
    <div className="p-empty">
      <FileText size={32} />
      <h3>{t('Nothing here yet', 'لا توجد عناصر بعد')}</h3>
      <p>{t('Try another filter or register a document to begin.', 'جرّب مرشحاً آخر أو سجل وثيقة للبدء.')}</p>
    </div>
  )
}
export function DocumentTable({
  rows,
  lang,
  t,
  onOpen,
  selectedId,
}: {
  rows: RecordItem[]
  lang: Language
  t: Translate
  onOpen: (r: RecordItem) => void
  selectedId?: string
}) {
  if (!rows.length) return <Empty t={t} />
  return (
    <div className="p-table-wrap">
      <table className="p-table">
        <thead>
          <tr>
            <th>{t('Document / tracking number', 'الوثيقة / رقم التتبع')}</th>
            <th>{t('Department', 'الإدارة')}</th>
            <th>{t('Classification', 'التصنيف')}</th>
            <th>{t('Status', 'الحالة')}</th>
            <th>{t('Version', 'الإصدار')}</th>
            <th>
              <span className="p-sr">{t('Open', 'فتح')}</span>
            </th>
          </tr>
        </thead>
        <tbody>
          {rows.map((r) => (
            <tr
              key={r.id}
              className={selectedId === r.id ? 'selected' : undefined}
              aria-current={selectedId === r.id ? 'true' : undefined}
            >
              <td>
                <button className="p-document-link" onClick={() => onOpen(r)}>
                  <span className="p-file">
                    <FileText size={20} />
                    <small>{r.fileName.split('.').at(-1)}</small>
                  </span>
                  <span>
                    <strong>{lang === 'ar' ? r.titleAr || r.title : r.title}</strong>
                    <small dir="ltr">
                      {r.id} · {local(r.kind, lang)}
                    </small>
                  </span>
                </button>
              </td>
              <td>{local(r.department, lang)}</td>
              <td>
                <Badge value={r.sensitivity} lang={lang} />
              </td>
              <td>
                <Badge value={r.status} lang={lang} />
                {r.hold && <small className="p-hold">{t('Legal hold', 'حجز قانوني')}</small>}
              </td>
              <td>
                {r.version ? `${r.version}.0` : '—'}
                {r.indexed && <small className="p-indexed">{t('Indexed', 'مفهرس')}</small>}
              </td>
              <td>
                <button
                  className="p-icon"
                  onClick={() => onOpen(r)}
                  aria-label={`${t('Open', 'فتح')} ${r.title}`}
                >
                  <ChevronRight size={17} />
                </button>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}
