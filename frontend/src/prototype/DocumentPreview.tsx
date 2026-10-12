import { useEffect, useState } from 'react'
import { FileText, LoaderCircle, ShieldCheck, ZoomIn, ZoomOut } from 'lucide-react'
import { readOriginal } from './files'
import type { Language, RecordItem } from './model'
import { local } from './translations'
import './review-drawer.css'

type Source = { id: string; url?: string; text?: string; mime?: string; name?: string; missing?: boolean }

export function DocumentPreview({
  record,
  lang,
  compact = false,
  file,
  records,
}: {
  record: RecordItem
  lang: Language
  compact?: boolean
  file?: File
  records?: RecordItem[]
}) {
  const [source, setSource] = useState<Source | null>(null)
  const [zoom, setZoom] = useState(100)
  const [imageFailed, setImageFailed] = useState(false)
  const title = lang === 'ar' ? record.titleAr || record.title : record.title
  const t = (en: string, ar: string) => (lang === 'ar' ? ar : en)
  const sample = !!record.sampleKey || /sample fixture|synthetic workshop fixture/i.test(record.hash)

  useEffect(() => {
    let cancelled = false
    let objectUrl: string | undefined
    setSource(null)
    setImageFailed(false)
    setZoom(100)
    const resolve = async () => {
      try {
        let original = file
        if (!original && !sample) {
          original = await readOriginal(record.id)
          let ancestor = record.revises
          const visited = new Set([record.id])
          while (!original && ancestor && !visited.has(ancestor)) {
            visited.add(ancestor)
            original = await readOriginal(ancestor)
            ancestor = records?.find((item) => item.id === ancestor)?.revises
          }
        }
        if (cancelled) return
        if (!original) {
          setSource({ id: record.id, missing: true })
          return
        }
        const ext = original.name.split('.').at(-1)?.toLowerCase()
        const mime = original.type || (ext === 'pdf' ? 'application/pdf' : ext === 'txt' ? 'text/plain' : '')
        if (mime.startsWith('text/') || ext === 'txt') {
          const text = await original.slice(0, 200000).text()
          if (!cancelled) setSource({ id: record.id, text, mime, name: original.name })
        } else {
          objectUrl = URL.createObjectURL(original)
          if (!cancelled) setSource({ id: record.id, url: objectUrl, mime, name: original.name })
          else URL.revokeObjectURL(objectUrl)
        }
      } catch {
        if (!cancelled) setSource({ id: record.id, missing: true })
      }
    }
    void resolve()
    return () => {
      cancelled = true
      if (objectUrl) URL.revokeObjectURL(objectUrl)
    }
  }, [record.id, record.revises, file, records, sample])

  const current = source?.id === record.id ? source : null
  const extension = (current?.name || record.fileName).split('.').at(-1)?.toUpperCase() || 'DOC'
  const isImage = current?.mime?.startsWith('image/') || /^(PNG|JPG|JPEG|WEBP|GIF)$/.test(extension)
  const isPdf = current?.mime === 'application/pdf' || extension === 'PDF'
  const isText = current?.text !== undefined
  const originalAvailable = current && !current.missing
  const heading =
    sample && !originalAvailable
      ? t('Synthetic document preview', 'معاينة وثيقة اصطناعية')
      : t('Original document preview', 'معاينة الوثيقة الأصلية')

  return (
    <div className={`d-preview ${compact ? 'is-compact' : ''}`} aria-label={`${heading}: ${title}`}>
      {!compact && (
        <div className="d-preview-toolbar">
          <span>
            <FileText size={15} />
            {t('Document preview', 'معاينة الوثيقة')}
          </span>
          <span className="d-preview-tools">
            <span>{extension}</span>
            {(!isPdf || sample) && (
              <>
                <button
                  type="button"
                  className="p-icon"
                  disabled={zoom <= 80}
                  onClick={() => setZoom((v) => v - 10)}
                  aria-label={t('Zoom out preview', 'تصغير المعاينة')}
                >
                  <ZoomOut size={15} />
                </button>
                <small>{zoom}%</small>
                <button
                  type="button"
                  className="p-icon"
                  disabled={zoom >= 140}
                  onClick={() => setZoom((v) => v + 10)}
                  aria-label={t('Zoom in preview', 'تكبير المعاينة')}
                >
                  <ZoomIn size={15} />
                </button>
              </>
            )}
          </span>
        </div>
      )}
      <div
        className={`d-preview-stage ${isPdf && originalAvailable && !compact ? 'is-pdf' : ''}`}
        tabIndex={compact ? undefined : 0}
        role={compact ? undefined : 'region'}
        aria-label={compact ? undefined : t('Document preview content', 'محتوى معاينة الوثيقة')}
      >
        {!current ? (
          <div className="d-preview-fallback" role="status">
            <LoaderCircle className="d-preview-loading" size={24} />
            <span>{t('Loading preview…', 'جارٍ تحميل المعاينة…')}</span>
          </div>
        ) : originalAvailable && isImage && !imageFailed ? (
          <img
            className="d-preview-image"
            src={current.url}
            alt={title}
            onError={() => setImageFailed(true)}
            style={compact ? undefined : { width: `${zoom}%` }}
          />
        ) : originalAvailable && isText ? (
          <article
            className="d-document-paper d-original-text"
            style={compact ? undefined : { fontSize: `${zoom}%` }}
          >
            <div className="d-paper-masthead">
              <strong>
                DOCAYA <span>دوكايا</span>
              </strong>
              <span>TXT</span>
            </div>
            <p className="d-paper-source">{t('Original text file', 'ملف النص الأصلي')}</p>
            <pre>{compact ? current.text!.slice(0, 500) : current.text}</pre>
            {!compact && current.text!.length >= 200000 && (
              <small>
                {t(
                  'Preview limited to the first 200 KB. Download for the complete file.',
                  'المعاينة محدودة بأول ٢٠٠ كيلوبايت. نزّل الملف لقراءة المحتوى كاملاً.',
                )}
              </small>
            )}
          </article>
        ) : originalAvailable && isPdf && !compact ? (
          <iframe
            className="d-pdf-frame"
            src={`${current.url}#toolbar=1&navpanes=0`}
            title={`${t('Original PDF', 'ملف PDF الأصلي')}: ${title}`}
          />
        ) : sample && !originalAvailable ? (
          <article className="d-document-paper" style={compact ? undefined : { fontSize: `${zoom}%` }}>
            <div className="d-paper-masthead">
              <strong>
                DOCAYA <span>دوكايا</span>
              </strong>
              <ShieldCheck size={compact ? 15 : 24} />
            </div>
            <p className="d-paper-source">
              {t('UAE public service · synthetic sample', 'الخدمات العامة الإماراتية · عينة اصطناعية')}
            </p>
            <div className="d-paper-reference">
              <span dir="ltr">{record.reference || record.id}</span>
              <span>{local(record.kind, lang)}</span>
            </div>
            <h3>{title}</h3>
            <div className="d-paper-rule" />
            <p className="d-paper-summary">
              {lang === 'ar' ? record.summaryAr || record.summary : record.summary}
            </p>
            {!compact && (
              <>
                <h4>{t('Document control', 'ضبط الوثيقة')}</h4>
                <dl className="d-paper-facts">
                  <dt>{t('Department', 'الإدارة')}</dt>
                  <dd>{local(record.department, lang)}</dd>
                  <dt>{t('Classification', 'التصنيف')}</dt>
                  <dd>{local(record.sensitivity, lang)}</dd>
                  <dt>{t('Review date', 'تاريخ المراجعة')}</dt>
                  <dd>{record.expiry}</dd>
                </dl>
                <p className="d-paper-watermark">
                  {t('SYNTHETIC · CLIENT WORKSHOP', 'اصطناعي · ورشة العميل')}
                </p>
              </>
            )}
            <footer>
              <span>{t('Demonstration copy', 'نسخة توضيحية')}</span>
              <span>{t('Page 1', 'الصفحة ١')}</span>
            </footer>
          </article>
        ) : (
          <div className="d-preview-fallback">
            <span className="d-format-icon">
              <FileText size={compact ? 26 : 42} />
              <b>{extension}</b>
            </span>
            <strong>{title}</strong>
            <span>
              {originalAvailable && isPdf
                ? t('PDF · open to preview', 'PDF · افتح للمعاينة')
                : originalAvailable
                  ? t(
                      'Original saved · preview unavailable for this format',
                      'الأصل محفوظ · المعاينة غير متاحة لهذه الصيغة',
                    )
                  : t('Original is unavailable in this browser', 'الأصل غير متاح في هذا المتصفح')}
            </span>
            {!compact && (
              <small>
                {originalAvailable
                  ? t(
                      'Download the original to open it in its native application.',
                      'نزّل الأصل لفتحه في التطبيق المخصص له.',
                    )
                  : t(
                      'This record contains metadata. Register the file again to restore its preview.',
                      'يحتوي هذا السجل على البيانات الوصفية. أعد تسجيل الملف لاستعادة معاينته.',
                    )}
              </small>
            )}
          </div>
        )}
      </div>
      {!compact && (
        <div className="d-preview-caption">
          <ShieldCheck size={13} />
          <span>
            {sample && !originalAvailable
              ? t('Fictional sample content for the client workshop.', 'محتوى افتراضي لورشة العميل.')
              : t(
                  'Local file preview · original bytes remain unchanged',
                  'معاينة محلية للملف · الأصل يبقى دون تغيير',
                )}
          </span>
        </div>
      )}
    </div>
  )
}
