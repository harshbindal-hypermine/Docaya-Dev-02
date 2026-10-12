import { local } from './translations'
import { useEffect, useRef, useState } from 'react'
import { ArrowLeft, ArrowRight, Check, Download, FileText, LockKeyhole, ShieldCheck, X } from 'lucide-react'
import {
  approvalSteps,
  capabilities,
  downloadFile,
  type Language,
  type RecordItem,
  type Role,
  type Workspace,
} from './model'
import { Badge, Field, type Translate } from './ui'
import { readOriginal } from './files'
import { DocumentPreview } from './DocumentPreview'
import './review-drawer.css'
export function RecordDetail({
  record,
  state,
  role,
  lang,
  t,
  onClose,
  onAction,
  onEdit,
  onLog,
  queue,
  onSelect,
  reviewMode = false,
}: {
  record: RecordItem
  state: Workspace
  role: Role
  lang: Language
  t: Translate
  onClose: () => void
  onAction: (action: string, reason?: string, step?: string) => boolean | void
  onEdit: () => void
  onLog: (action: string, ar: string) => void
  queue?: RecordItem[]
  onSelect?: (record: RecordItem) => void
  reviewMode?: boolean
}) {
  const [tab, setTab] = useState(reviewMode ? 'review' : 'overview')
  const [reason, setReason] = useState('')
  const [error, setError] = useState('')
  const [returning, setReturning] = useState(false)
  const [delegateName, setDelegateName] = useState('')
  const [delegateError, setDelegateError] = useState('')
  const [selectedStep, setSelectedStep] = useState('')
  const [summaryExpanded, setSummaryExpanded] = useState(false)
  const [previewExpanded, setPreviewExpanded] = useState(false)
  const [decision, setDecision] = useState<{ action: string; step: string; name: string } | null>(null)
  const [confirmDispose, setConfirmDispose] = useState(false)
  const headingRef = useRef<HTMLHeadingElement>(null)
  const decisionRef = useRef<HTMLDivElement>(null)
  const returnReasonRef = useRef<HTMLTextAreaElement>(null)
  const delegateRef = useRef<HTMLInputElement>(null)
  const initialFocus = useRef<HTMLElement | null>(null)
  useEffect(() => {
    initialFocus.current = document.activeElement as HTMLElement | null
    headingRef.current?.focus({ preventScroll: true })
    return () => {
      if (initialFocus.current?.isConnected) initialFocus.current.focus({ preventScroll: true })
      else if (reviewMode) {
        const queueFocus =
          document.querySelector<HTMLElement>(
            '.d-simple-queue .d-queue-filters button[aria-pressed="true"]',
          ) || document.querySelector<HTMLElement>('.d-simple-queue')
        if (queueFocus) {
          if (!queueFocus.matches('button')) queueFocus.tabIndex = -1
          queueFocus.focus({ preventScroll: true })
        }
      }
    }
  }, [reviewMode])
  useEffect(() => {
    const escape = (event: KeyboardEvent) => {
      if (event.key === 'Escape' && !event.defaultPrevented) {
        event.preventDefault()
        onClose()
      }
    }
    window.addEventListener('keydown', escape)
    return () => window.removeEventListener('keydown', escape)
  }, [onClose])
  useEffect(() => {
    setReason('')
    setError('')
    setReturning(false)
    setDelegateName('')
    setDelegateError('')
    setSelectedStep('')
    setSummaryExpanded(false)
    setPreviewExpanded(false)
    setDecision(null)
    setTab(reviewMode ? 'review' : 'overview')
    setConfirmDispose(false)
    headingRef.current?.focus({ preventScroll: true })
  }, [record.id, reviewMode])
  useEffect(() => {
    if (returning) returnReasonRef.current?.focus()
  }, [returning])
  useEffect(() => {
    if (decision) decisionRef.current?.focus({ preventScroll: true })
  }, [decision])
  const rights = capabilities(role)
  const steps = approvalSteps(record)
  const remainingSteps = steps.filter((step) => !record.approvals.includes(step))
  const eligibleSteps = record.flow === 'Parallel' ? remainingSteps : remainingSteps.slice(0, 1)
  const currentStep = eligibleSteps.includes(selectedStep) ? selectedStep : eligibleSteps[0] || ''
  const canDecide = record.status === 'PendingApproval' && rights.approve && !!currentStep
  const WorkflowDetails = reviewMode ? 'details' : 'div'
  const title = lang === 'ar' ? record.titleAr || record.title : record.title
  const ordered = queue || [record]
  const position = ordered.findIndex((item) => item.id === record.id)
  const previous = position > 0 ? ordered[position - 1] : undefined
  const next = position >= 0 ? ordered[position + 1] : ordered[0]
  const pending = [
    ...ordered.slice(Math.max(0, position + 1)),
    ...ordered.slice(0, Math.max(0, position)),
  ].find((item) => item.id !== record.id && item.status === 'PendingApproval')
  const act = (action: string, needsReason = false, step = '') => {
    if (needsReason && !reason.trim()) {
      setError(t('Please enter a reason or delegate name first.', 'يرجى إدخال السبب أو اسم المفوض أولاً.'))
      return
    }
    setError('')
    onAction(action, reason, step)
  }
  const reviewAction = (action: 'approve' | 'return' | 'delegate') => {
    const value = action === 'delegate' ? delegateName.trim() : reason.trim()
    if (action === 'return' && !value) {
      setError(
        t(
          'Explain what needs to change before returning the document.',
          'وضح التعديلات المطلوبة قبل إرجاع الوثيقة.',
        ),
      )
      returnReasonRef.current?.focus()
      return
    }
    if (action === 'delegate' && !value) {
      setDelegateError(
        t('Enter the name of the reviewer to delegate to.', 'أدخل اسم المراجع الذي تريد تفويضه.'),
      )
      delegateRef.current?.focus()
      return
    }
    setError('')
    setDelegateError('')
    if (onAction(action, action === 'approve' ? '' : value, currentStep) === false) {
      setError(
        t('The decision could not be saved. Please try again.', 'تعذر حفظ القرار. يرجى المحاولة مرة أخرى.'),
      )
      return
    }
    setDecision({ action, step: currentStep, name: value })
    setReturning(false)
    setTab('review')
  }
  const download = async () => {
    try {
      let original = await readOriginal(record.id)
      let ancestor = record.revises || ''
      const visited = new Set<string>([record.id])
      while (!original && ancestor.startsWith('DOC-') && !visited.has(ancestor)) {
        visited.add(ancestor)
        original = await readOriginal(ancestor)
        ancestor = state.documents.find((r) => r.id === ancestor)?.revises || ''
      }
      if (original) {
        const url = URL.createObjectURL(original)
        const a = document.createElement('a')
        a.href = url
        a.download = record.fileName
        a.click()
        setTimeout(() => URL.revokeObjectURL(url), 1000)
      } else
        downloadFile(
          `${record.id}-sample.txt`,
          `DOCAYA · SAMPLE DOCUMENT\n${title}\n${record.id} · v${record.version}.0\n\n${record.summary}\n\n${record.summaryAr}`,
          'text/plain;charset=utf-8',
        )
      onLog('Original / sample downloaded', 'تم تنزيل الملف الأصلي / العينة')
    } catch {
      setError(t('File download failed. Please try again.', 'تعذر تنزيل الملف. حاول مجدداً.'))
    }
  }
  return (
    <section
      className={`d-review-drawer${reviewMode ? ' is-approver' : ''}${previewExpanded ? ' is-preview-expanded' : ''}`}
      role="dialog"
      aria-modal="false"
      aria-label={title}
    >
      <header className="d-review-header">
        <div className="d-review-heading">
          <div>
            <p className="p-eyebrow">
              {reviewMode ? t('Review document', 'مراجعة الوثيقة') : t('Document workspace', 'مساحة الوثيقة')}
            </p>
            <h2 ref={headingRef} tabIndex={-1}>
              {title}
            </h2>
          </div>
          <button
            className="p-icon"
            aria-label={t('Close review drawer', 'إغلاق درج المراجعة')}
            onClick={onClose}
          >
            <X size={19} />
          </button>
        </div>
        <div className="d-review-meta">
          <span dir="ltr">{record.id}</span>
          <Badge value={record.status} lang={lang} />
          <Badge value={record.sensitivity} lang={lang} />
          {record.hold && (
            <span className="p-badge secret">
              <LockKeyhole size={12} />
              {t('Legal hold', 'حجز قانوني')}
            </span>
          )}
          <span>{record.version ? `v${record.version}.0` : t('Unpublished', 'غير منشور')}</span>
        </div>
      </header>
      {onSelect && ordered.length > 0 && !(reviewMode && decision) && (
        <div className="d-review-navigation">
          <span>
            {position >= 0
              ? `${position + 1} / ${ordered.length} · ${t('in your view', 'في العرض الحالي')}`
              : record.status === 'PendingApproval'
                ? t('Outside the current filter', 'خارج المرشح الحالي')
                : t('Review completed · queue updated', 'اكتملت المراجعة · تم تحديث القائمة')}
          </span>
          <div>
            <button className="p-btn" disabled={!previous} onClick={() => previous && onSelect(previous)}>
              <ArrowLeft size={13} />
              {t('Previous', 'السابق')}
            </button>
            <button className="p-btn" disabled={!next} onClick={() => next && onSelect(next)}>
              {t('Next document', 'الوثيقة التالية')}
              <ArrowRight size={13} />
            </button>
          </div>
        </div>
      )}
      {reviewMode && (
        <div className="d-review-mobile-tools">
          <button
            className="p-link"
            aria-expanded={previewExpanded}
            aria-controls="d-review-document-preview"
            onClick={() => setPreviewExpanded((expanded) => !expanded)}
          >
            {previewExpanded
              ? t('Back to review', 'العودة إلى المراجعة')
              : t('Expand preview', 'توسيع المعاينة')}
          </button>
        </div>
      )}
      <div className="d-review-workspace">
        <div className="d-review-preview" id="d-review-document-preview">
          <DocumentPreview record={record} lang={lang} records={state.documents} />
        </div>
        <div className="d-review-inspector">
          <div className="d-review-tabs" role="group" aria-label={t('Document details', 'تفاصيل الوثيقة')}>
            {(reviewMode
              ? [
                  ['review', 'Review', 'المراجعة'],
                  ['details', 'Details', 'التفاصيل'],
                  ['history', 'Activity', 'النشاط'],
                ]
              : [
                  ['overview', 'Overview', 'نظرة عامة'],
                  ['workflow', 'Approval & publishing', 'الاعتماد والنشر'],
                  ['governance', 'Governance', 'الحوكمة'],
                  ['history', 'Activity', 'النشاط'],
                ]
            ).map(([id, en, ar]) => (
              <button
                aria-pressed={tab === id}
                aria-controls="d-review-panel"
                id={`d-review-tab-${id}`}
                className={tab === id ? 'active' : ''}
                key={id}
                onClick={() => setTab(id)}
              >
                {t(en, ar)}
              </button>
            ))}
          </div>
          <div
            className="d-review-content"
            id="d-review-panel"
            role="region"
            aria-labelledby={`d-review-tab-${tab}`}
          >
            {tab === 'review' && reviewMode && (
              <>
                <dl className="d-approver-facts">
                  <div>
                    <dt>{t('Submitted by', 'مقدم الوثيقة')}</dt>
                    <dd>{record.owner}</dd>
                  </div>
                  <div>
                    <dt>{t('Department', 'الإدارة')}</dt>
                    <dd>{local(record.department, lang)}</dd>
                  </div>
                  <div>
                    <dt>{t('Decision due', 'موعد القرار')}</dt>
                    <dd>
                      {record.due
                        ? new Date(record.due).toLocaleDateString(lang, {
                            day: 'numeric',
                            month: 'short',
                            year: 'numeric',
                          })
                        : t('No due date', 'لم يحدد موعد')}
                    </dd>
                  </div>
                </dl>
                <div
                  className={`d-review-summary d-approver-summary${summaryExpanded ? ' is-expanded' : ''}`}
                >
                  <h3>{t('Document summary', 'ملخص الوثيقة')}</h3>
                  <p id="d-approver-summary-text">
                    {lang === 'ar' ? record.summaryAr || record.summary : record.summary}
                  </p>
                  <button
                    className="p-link"
                    aria-expanded={summaryExpanded}
                    aria-controls="d-approver-summary-text"
                    onClick={() => setSummaryExpanded((expanded) => !expanded)}
                  >
                    {summaryExpanded
                      ? t('Show less', 'عرض أقل')
                      : t('Read full summary', 'قراءة الملخص كاملاً')}
                  </button>
                </div>
                {record.status === 'Returned' && (
                  <div className="d-current-reviewer">
                    <strong>
                      {t('Waiting for the owner to make changes', 'بانتظار تعديلات مالك الوثيقة')}
                    </strong>
                    <p>{record.note}</p>
                  </div>
                )}
                {record.status === 'Approved' && (
                  <p className="p-note">
                    {t(
                      'Approval is complete. Publication is awaiting an administrator retry.',
                      'اكتمل الاعتماد. ينتظر النشر إعادة المحاولة من المسؤول.',
                    )}
                  </p>
                )}
                {canDecide && !decision && (
                  <details className="d-review-disclosure d-delegate-options">
                    <summary>{t('Need another reviewer?', 'هل تحتاج إلى مراجع آخر؟')}</summary>
                    <p>
                      {t(
                        'Delegate this review to a colleague in the demo.',
                        'فوض هذه المراجعة إلى زميل في العرض التجريبي.',
                      )}
                    </p>
                    <Field label={t('Delegate name', 'اسم المفوض')}>
                      <input
                        ref={delegateRef}
                        value={delegateName}
                        onChange={(event) => {
                          setDelegateName(event.target.value)
                          setDelegateError('')
                        }}
                        aria-invalid={!!delegateError}
                        aria-describedby={delegateError ? 'd-delegate-error' : undefined}
                      />
                    </Field>
                    {delegateError && (
                      <p id="d-delegate-error" className="p-error" role="alert">
                        {delegateError}
                      </p>
                    )}
                    <button className="p-btn" onClick={() => reviewAction('delegate')}>
                      {t('Delegate approval', 'تفويض الاعتماد')}
                    </button>
                  </details>
                )}
              </>
            )}
            {(tab === 'overview' || (reviewMode && tab === 'details')) && (
              <>
                <div className="d-review-summary">
                  <h3>{t('Registered description', 'الوصف المسجل')}</h3>
                  <p>{lang === 'ar' ? record.summaryAr || record.summary : record.summary}</p>
                </div>
                <div>
                  <dl className="p-facts vertical">
                    <dt>{t('Owner', 'المالك')}</dt>
                    <dd>{record.owner}</dd>
                    <dt>{t('Department / class', 'الإدارة / الفئة')}</dt>
                    <dd>
                      {local(record.department, lang)} / {local(record.kind, lang)}
                    </dd>
                    <dt>{t('Original file', 'الملف الأصلي')}</dt>
                    <dd>
                      {record.fileName}
                      <small>
                        {(record.size / 1024).toFixed(1)} KB · {record.mime}
                      </small>
                    </dd>
                    <dt>{t('Captured', 'تاريخ التسجيل')}</dt>
                    <dd>{new Date(record.captured).toLocaleString(lang)}</dd>
                    <dt>{t('Expiry / review', 'الانتهاء / المراجعة')}</dt>
                    <dd>{record.expiry}</dd>
                    <dt>SHA-256</dt>
                    <dd className="p-hash">{record.hash}</dd>
                  </dl>
                  {record.status !== 'Disposed' && (
                    <button className="p-btn" onClick={() => void download()}>
                      <Download size={15} />
                      {t('Download original / sample', 'تنزيل الأصل / العينة')}
                    </button>
                  )}
                </div>
              </>
            )}
            {(tab === 'workflow' || (reviewMode && tab === 'details')) && (
              <WorkflowDetails className={reviewMode ? 'd-review-disclosure' : undefined}>
                {reviewMode && (
                  <summary>{t('Approval progress & publishing', 'تقدم الاعتماد والنشر')}</summary>
                )}
                <div className="p-note">
                  <ShieldCheck size={20} />
                  {t(
                    'Demonstration approvals and signatures. SharePoint promotion is simulated; the original file stays unchanged in this browser.',
                    'موافقات وتوقيعات تجريبية. النشر إلى شيربوينت محاكاة ويظل الملف الأصلي دون تغيير في المتصفح.',
                  )}
                </div>
                <div className="p-approval-list">
                  {steps.map((step, i) => (
                    <div key={step}>
                      <span
                        className={
                          record.approvals.includes(step) ||
                          ['Published', 'Superseded', 'Archived'].includes(record.status)
                            ? 'p-check done'
                            : 'p-check'
                        }
                      >
                        {record.approvals.includes(step) ||
                        ['Published', 'Superseded', 'Archived'].includes(record.status) ? (
                          <Check size={17} />
                        ) : (
                          i + 1
                        )}
                      </span>
                      <div>
                        <strong>{local(step, lang)}</strong>
                        <small>
                          {local(record.flow, lang)} ·{' '}
                          {record.delegated
                            ? `${t('Delegate', 'المفوض')}: ${record.note}`
                            : local(record.department, lang)}
                        </small>
                      </div>
                      {!reviewMode &&
                        record.status === 'PendingApproval' &&
                        rights.approve &&
                        !record.approvals.includes(step) &&
                        (record.flow === 'Parallel' ||
                          step === steps.find((s) => !record.approvals.includes(s))) && (
                          <button className="p-btn primary" onClick={() => act('approve', false, step)}>
                            {t('Approve & sign', 'اعتماد وتوقيع')}
                          </button>
                        )}
                    </div>
                  ))}
                </div>
                <dl className="p-facts">
                  <dt>{t('Destination', 'الوجهة')}</dt>
                  <dd>{record.location}</dd>
                  <dt>{t('Staging copy', 'نسخة التجهيز')}</dt>
                  <dd>{local(record.staging, lang)}</dd>
                  <dt>{t('Index', 'الفهرس')}</dt>
                  <dd>
                    {record.indexed
                      ? t('Indexed · available to Ask Docaya', 'مفهرس · متاح لاسأل دوكايا')
                      : t('Not indexed · published content only', 'غير مفهرس · للمحتوى المنشور فقط')}
                  </dd>
                  <dt>{t('Due', 'الموعد')}</dt>
                  <dd>{record.due ? new Date(record.due).toLocaleString(lang) : '—'}</dd>
                </dl>
                {record.signature && (
                  <div className="p-note">
                    <FileText size={18} />
                    <span>
                      {t('Demo signature certificate', 'شهادة توقيع تجريبية')}
                      <small>{record.signature}</small>
                      <button
                        className="p-link"
                        onClick={() =>
                          downloadFile(
                            `${record.id}-demo-certificate.txt`,
                            `DOCAYA — DEMONSTRATION ONLY\nNot a legal electronic signature\n${record.id}\n${record.signature}`,
                            'text/plain',
                          )
                        }
                      >
                        {t('Download certificate', 'تنزيل الشهادة')}
                      </button>
                    </span>
                  </div>
                )}
                {record.note && <p className="p-warning">{record.note}</p>}
                {!reviewMode && record.status === 'PendingApproval' && rights.approve && (
                  <>
                    <Field label={t('Return reason / delegate name', 'سبب الإرجاع / اسم المفوض')}>
                      <textarea
                        value={reason}
                        onChange={(e) => setReason(e.target.value)}
                        placeholder={t(
                          'Explain the changes needed, or enter a delegate',
                          'وضح التعديلات المطلوبة أو أدخل اسم المفوض',
                        )}
                      />
                    </Field>
                    <div className="p-actions">
                      <button className="p-btn danger" onClick={() => act('return', true)}>
                        {t('Return for changes', 'إرجاع للتعديل')}
                      </button>
                      <button className="p-btn" onClick={() => act('delegate', true)}>
                        {t('Delegate approval', 'تفويض الاعتماد')}
                      </button>
                    </div>
                  </>
                )}
                {record.status === 'Approved' && role === 'System Administrator' && (
                  <button className="p-btn primary" onClick={() => act('retry')}>
                    {t('Retry publication', 'إعادة محاولة النشر')}
                  </button>
                )}
              </WorkflowDetails>
            )}
            {tab === 'governance' && (
              <>
                <dl className="p-facts">
                  <dt>{t('Retention policy', 'سياسة الحفظ')}</dt>
                  <dd>
                    {state.settings.retentionYears}{' '}
                    {t('years · review before disposition', 'سنوات · مراجعة قبل الإتلاف')}
                  </dd>
                  <dt>{t('Access scope', 'نطاق الوصول')}</dt>
                  <dd>{local(record.scope, lang)}</dd>
                  <dt>{t('Record declaration', 'إعلان السجل')}</dt>
                  <dd>
                    {record.declared
                      ? t('Declared · metadata frozen', 'معلن · البيانات مجمدة')
                      : t('Not declared', 'غير معلن')}
                  </dd>
                  <dt>{t('Legal hold', 'الحجز القانوني')}</dt>
                  <dd>{record.hold || t('No active hold', 'لا يوجد حجز نشط')}</dd>
                </dl>
                {rights.records && record.status !== 'Disposed' && (
                  <>
                    <Field label={t('Governance reason / case reference', 'سبب الإجراء / مرجع القضية')}>
                      <textarea value={reason} onChange={(e) => setReason(e.target.value)} />
                    </Field>
                    <div className="p-actions">
                      <button className="p-btn" onClick={() => act(record.hold ? 'release' : 'hold', true)}>
                        <LockKeyhole size={15} />
                        {record.hold
                          ? t('Release hold', 'رفع الحجز')
                          : t('Apply legal hold', 'تطبيق حجز قانوني')}
                      </button>
                      {record.status === 'Published' && !record.declared && (
                        <button className="p-btn" onClick={() => act('declare')}>
                          {t('Declare record', 'إعلان سجل')}
                        </button>
                      )}
                      {record.status === 'Published' && (
                        <button
                          className="p-btn"
                          disabled={!!record.hold}
                          onClick={() => act('archive', true)}
                        >
                          {t('Archive record', 'أرشفة السجل')}
                        </button>
                      )}
                      {record.status === 'Archived' && (
                        <button
                          className="p-btn danger"
                          disabled={!!record.hold}
                          onClick={() => {
                            if (!reason.trim())
                              setError(t('Enter a disposition reason first.', 'أدخل سبب الإتلاف أولاً.'))
                            else setConfirmDispose(true)
                          }}
                        >
                          {t('Review disposition', 'مراجعة الإتلاف')}
                        </button>
                      )}
                    </div>
                    {record.hold && (
                      <p className="p-warning">
                        {t(
                          'Legal hold blocks archiving, deletion and revisions.',
                          'يمنع الحجز القانوني الأرشفة والحذف والإصدارات الجديدة.',
                        )}
                      </p>
                    )}
                    {confirmDispose && (
                      <div className="p-warning">
                        <p>
                          {t(
                            'Approve simulated disposition? The record remains in the registry and audit log.',
                            'هل تعتمد الإتلاف التجريبي؟ يبقى السجل في الفهرس وسجل التدقيق.',
                          )}
                        </p>
                        <button
                          className="p-btn danger"
                          onClick={() => {
                            act('dispose', true)
                            setConfirmDispose(false)
                          }}
                        >
                          {t('Approve disposition', 'اعتماد الإتلاف')}
                        </button>
                        <button className="p-btn" onClick={() => setConfirmDispose(false)}>
                          {t('Cancel', 'إلغاء')}
                        </button>
                      </div>
                    )}
                  </>
                )}
              </>
            )}
            {tab === 'history' && (
              <div className="p-timeline">
                {!state.audit.some((event) => event.object === record.id) && (
                  <p className="p-subtle">
                    {t(
                      'No activity has been recorded yet. Review decisions and changes will appear here.',
                      'لم يتم تسجيل نشاط بعد. ستظهر قرارات المراجعة والتغييرات هنا.',
                    )}
                  </p>
                )}
                {state.audit
                  .filter((a) => a.object === record.id)
                  .map((a) => (
                    <div key={a.id}>
                      <i />
                      <div>
                        <strong>{lang === 'ar' ? a.actionAr : a.action}</strong>
                        <p>
                          {a.actor} · {new Date(a.time).toLocaleString(lang)}
                        </p>
                        {a.detail && <small>{a.detail}</small>}
                      </div>
                    </div>
                  ))}
              </div>
            )}
          </div>
          {reviewMode && (
            <div className="d-approver-actions" aria-label={t('Review decision', 'قرار المراجعة')}>
              {decision ? (
                <>
                  <div
                    className="d-decision-feedback"
                    role="status"
                    aria-live="polite"
                    ref={decisionRef}
                    tabIndex={-1}
                  >
                    <Check size={19} aria-hidden="true" />
                    <div>
                      <strong>
                        {decision.action === 'return'
                          ? t('Returned for changes', 'تم الإرجاع للتعديل')
                          : decision.action === 'delegate'
                            ? t('Review delegated', 'تم تفويض المراجعة')
                            : t('Approval saved', 'تم حفظ الاعتماد')}
                      </strong>
                      <p>
                        {decision.action === 'return'
                          ? t(
                              'Your reason is saved for the document owner.',
                              'تم حفظ سبب الإرجاع لمالك الوثيقة.',
                            )
                          : decision.action === 'delegate'
                            ? `${t('Delegated to', 'تم التفويض إلى')} ${decision.name}`
                            : record.status === 'PendingApproval'
                              ? `${local(decision.step, lang)} · ${t('Another review step is still required.', 'لا تزال هناك خطوة مراجعة أخرى مطلوبة.')}`
                              : record.status === 'Approved'
                                ? t(
                                    'All review steps are complete. Publication needs an administrator retry.',
                                    'اكتملت جميع خطوات المراجعة. يحتاج النشر إلى إعادة المحاولة من المسؤول.',
                                  )
                                : t(
                                    'All review steps are complete. The document is published.',
                                    'اكتملت جميع خطوات المراجعة وتم نشر الوثيقة.',
                                  )}
                      </p>
                    </div>
                  </div>
                  {onSelect && pending ? (
                    <button className="p-btn primary d-review-next" onClick={() => onSelect(pending)}>
                      {t('Next pending document', 'الوثيقة التالية للاعتماد')}
                      <ArrowRight size={15} />
                    </button>
                  ) : (
                    <button className="p-btn primary" onClick={onClose}>
                      {t('Back to approval queue', 'العودة إلى قائمة الاعتماد')}
                    </button>
                  )}
                  {canDecide && (
                    <button
                      className="p-link d-review-continue"
                      onClick={() => {
                        setDecision(null)
                        setReason('')
                        setSelectedStep('')
                      }}
                    >
                      {decision.action === 'delegate'
                        ? t('Continue reviewing this document', 'متابعة مراجعة هذه الوثيقة')
                        : t('Review the remaining step', 'مراجعة الخطوة المتبقية')}
                    </button>
                  )}
                </>
              ) : canDecide ? (
                returning ? (
                  <>
                    <Field label={t('What needs to change? (required)', 'ما التعديلات المطلوبة؟ (إلزامي)')}>
                      <textarea
                        ref={returnReasonRef}
                        value={reason}
                        required
                        aria-invalid={!!error}
                        aria-describedby={error ? 'd-review-decision-error' : 'd-return-help'}
                        onChange={(event) => {
                          setReason(event.target.value)
                          setError('')
                        }}
                        placeholder={t(
                          'Describe the changes the owner should make.',
                          'وضح التعديلات التي يجب أن يجريها مالك الوثيقة.',
                        )}
                      />
                    </Field>
                    <small id="d-return-help">
                      {t(
                        'The owner will see this reason with the returned document.',
                        'سيظهر هذا السبب لمالك الوثيقة عند إرجاعها.',
                      )}
                    </small>
                    <div className="d-approver-buttons">
                      <button className="p-btn danger" onClick={() => reviewAction('return')}>
                        {t('Confirm return', 'تأكيد الإرجاع')}
                      </button>
                      <button
                        className="p-btn"
                        onClick={() => {
                          setReturning(false)
                          setError('')
                        }}
                      >
                        {t('Cancel', 'إلغاء')}
                      </button>
                    </div>
                  </>
                ) : (
                  <>
                    {eligibleSteps.length > 1 ? (
                      <Field label={t('Reviewing as', 'المراجعة بصفة')}>
                        <select value={currentStep} onChange={(event) => setSelectedStep(event.target.value)}>
                          {eligibleSteps.map((step) => (
                            <option key={step} value={step}>
                              {local(step, lang)}
                            </option>
                          ))}
                        </select>
                      </Field>
                    ) : (
                      <p className="d-decision-as">
                        {t('Reviewing as', 'المراجعة بصفة')} <strong>{local(currentStep, lang)}</strong>
                      </p>
                    )}
                    <div className="d-approver-buttons">
                      <button className="p-btn primary" onClick={() => reviewAction('approve')}>
                        <Check size={16} />
                        {t('Approve & sign', 'اعتماد وتوقيع')}
                      </button>
                      <button
                        className="p-btn"
                        onClick={() => {
                          setReturning(true)
                          setError('')
                        }}
                      >
                        {t('Return for changes', 'إرجاع للتعديل')}
                      </button>
                    </div>
                    <small>
                      {t(
                        'Demo decision · recorded in document activity',
                        'قرار تجريبي · يسجل في نشاط الوثيقة',
                      )}
                    </small>
                  </>
                )
              ) : (
                <>
                  <p className="d-decision-as">
                    {record.status === 'Returned'
                      ? t(
                          'No approval is needed until the owner resubmits.',
                          'لا يلزم الاعتماد حتى يعيد المالك إرسال الوثيقة.',
                        )
                      : t(
                          'There is no pending decision for this document.',
                          'لا يوجد قرار معلق لهذه الوثيقة.',
                        )}
                  </p>
                  {onSelect && pending ? (
                    <button className="p-btn primary d-review-next" onClick={() => onSelect(pending)}>
                      {t('Next pending document', 'الوثيقة التالية للاعتماد')}
                      <ArrowRight size={15} />
                    </button>
                  ) : (
                    <button className="p-btn" onClick={onClose}>
                      {t('Back to approval queue', 'العودة إلى قائمة الاعتماد')}
                    </button>
                  )}
                </>
              )}
              {error && (
                <p id="d-review-decision-error" className="p-error" role="alert">
                  {error}
                </p>
              )}
            </div>
          )}
        </div>
      </div>
      {error && !reviewMode && (
        <p className="p-error d-review-error" role="alert">
          {error}
        </p>
      )}
      {!reviewMode && (
        <footer className="d-review-footer">
          <button className="p-btn" onClick={onClose}>
            {t('Close', 'إغلاق')}
          </button>
          <span />
          {rights.register && ['Draft', 'Classified', 'Returned'].includes(record.status) && (
            <>
              <button className="p-btn" onClick={onEdit}>
                {t('Edit registration', 'تعديل التسجيل')}
              </button>
              <button className="p-btn primary" onClick={() => act('submit')}>
                {t('Submit for approval', 'إرسال للاعتماد')}
              </button>
            </>
          )}
          {rights.register && record.status === 'Published' && !record.hold && !record.declared && (
            <button
              className="p-btn"
              onClick={() => {
                act('version')
                onClose()
              }}
            >
              {t('Create revision draft', 'إنشاء مسودة إصدار')}
            </button>
          )}
        </footer>
      )}
    </section>
  )
}
