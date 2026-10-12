import { useEffect, useRef, useState } from 'react'
import {
  ArrowRight,
  BookmarkPlus,
  Check,
  ChevronDown,
  FileSearch,
  Grid2X2,
  List,
  Search,
  SlidersHorizontal,
  ThumbsDown,
  ThumbsUp,
  X,
} from 'lucide-react'
import type { PageProps } from './Management'
import type { Language, RecordItem } from './model'
import { Badge, DocumentTable, Empty, type Translate } from './ui'
import { DocumentPreview } from './DocumentPreview'
import { local } from './translations'
import { discover } from './knowledge-search'
import { DocayaAIMark } from './BrandMarks'
import './discovery.css'

function SourceCard({
  record,
  lang,
  t,
  onOpen,
  compact = false,
}: {
  record: RecordItem
  lang: Language
  t: Translate
  onOpen: (record: RecordItem) => void
  compact?: boolean
}) {
  const title = lang === 'ar' ? record.titleAr || record.title : record.title
  return (
    <button
      className={`d-source-card ${compact ? 'compact' : ''}`}
      onClick={() => onOpen(record)}
      aria-label={`${t('Preview', 'معاينة')} ${title}`}
    >
      <div className="d-thumbnail" aria-hidden="true">
        <DocumentPreview record={record} lang={lang} compact />
        <span className="d-file-type">{record.fileName.split('.').at(-1)?.toUpperCase()}</span>
      </div>
      <div className="d-source-body">
        <small>{local(record.department, lang)}</small>
        <strong>{title}</strong>
        <span className="d-source-meta">
          <span>{record.id}</span>
          <b>v{record.version}.0</b>
        </span>
        {!compact && (
          <>
            <p>{lang === 'ar' ? record.summaryAr || record.summary : record.summary}</p>
            <span className="d-source-footer">
              <Badge value={record.sensitivity} lang={lang} />
              <span>
                <FileSearch size={14} />
                {t('Preview document', 'معاينة الوثيقة')}
              </span>
            </span>
          </>
        )}
      </div>
    </button>
  )
}

export function SearchPage({
  state,
  setState,
  visible,
  lang,
  t,
  onOpen,
  notify,
  initialQuery,
  selectedId,
}: PageProps & { initialQuery: string }) {
  const [query, setQuery] = useState(initialQuery)
  const [kind, setKind] = useState('all')
  const [department, setDepartment] = useState('all')
  const [sensitivity, setSensitivity] = useState('all')
  const [view, setView] = useState<'grid' | 'list'>('grid')
  const [question, setQuestion] = useState('')
  const [answer, setAnswer] = useState<string | null>(null)
  const [filtersOpen, setFiltersOpen] = useState(false)
  useEffect(() => setQuery(initialQuery), [initialQuery])
  const rows = discover(visible, query).filter(
    (r) =>
      (kind === 'all' || r.kind === kind) &&
      (department === 'all' || r.department === department) &&
      (sensitivity === 'all' || r.sensitivity === sensitivity),
  )
  const sources = answer ? discover(visible, answer).slice(0, 3) : []
  const options = [
    ...new Set(visible.filter((r) => r.status === 'Published' && r.indexed).map((r) => r.department)),
  ]
  const activeFilters = [kind, department, sensitivity].filter((f) => f !== 'all').length
  const ask = (value: string) => {
    if (value.trim()) {
      setQuestion(value)
      setAnswer(value)
    }
  }
  return (
    <>
      <section className="d-discovery-hero">
        <div className="d-discovery-title">
          <span className="d-ai-emblem">
            <DocayaAIMark size={42} />
          </span>
          <div>
            <p className="p-eyebrow">
              {t('DOCAYA INTELLIGENCE / YOUR KNOWLEDGE, IN VIEW', 'ذكاء دوكايا / معرفتك أمامك')}
            </p>
            <h2>{t('The answer is in your documents.', 'الإجابة في وثائقك.')}</h2>
            <p>
              {t(
                'Recognise the document. Find the detail. Follow the source.',
                'تعرف على الوثيقة. اعثر على التفاصيل. تتبع المصدر.',
              )}
            </p>
          </div>
        </div>
        <form
          className="d-ask-bar"
          onSubmit={(e) => {
            e.preventDefault()
            ask(question)
          }}
        >
          <DocayaAIMark size={28} />
          <input
            value={question}
            onChange={(e) => setQuestion(e.target.value)}
            aria-label={t('Ask Docaya question', 'سؤال لدوكايا')}
            placeholder={t(
              'Ask about road safety, civil defence, or a policy…',
              'اسأل عن السلامة المرورية أو الدفاع المدني أو سياسة…',
            )}
            required
          />
          <button className="p-btn primary">
            {t('Ask Docaya', 'اسأل دوكايا')}
            <ArrowRight size={16} />
          </button>
        </form>
        <div className="d-prompts">
          {[
            ['What are the retention rules?', 'ما قواعد الحفظ؟'],
            ['Find road safety guidance', 'ابحث عن إرشادات السلامة المرورية'],
            ['Civil defence readiness', 'جاهزية الدفاع المدني'],
          ].map(([en, ar]) => (
            <button key={en} onClick={() => ask(t(en, ar))}>
              {t(en, ar)}
              <ArrowRight size={12} />
            </button>
          ))}
        </div>
        <small className="d-trust">
          <Check size={12} />
          {t(
            'Published sources · permission-aware · synthetic MOI demonstration data',
            'مصادر منشورة · تراعي الصلاحيات · بيانات وزارة الداخلية التجريبية',
          )}
        </small>
      </section>
      {answer && (
        <section className="p-card d-answer" aria-label={t('Docaya answer', 'إجابة دوكايا')}>
          <div className="p-card-head">
            <div>
              <p className="p-eyebrow">{t('ANSWER WITH EVIDENCE', 'إجابة مدعومة بالمصادر')}</p>
              <h3>{answer}</h3>
            </div>
            <button
              className="p-icon"
              aria-label={t('Clear answer', 'مسح الإجابة')}
              onClick={() => setAnswer(null)}
            >
              <X size={18} />
            </button>
          </div>
          {sources.length ? (
            sources.map((r, i) => (
              <div className="d-answer-source" key={r.id}>
                <span className="d-cite-number">{i + 1}</span>
                <div>
                  <p>{lang === 'ar' ? r.summaryAr || r.summary : r.summary}</p>
                  <button className="p-citation" onClick={() => onOpen(r)}>
                    {lang === 'ar' ? r.titleAr || r.title : r.title}
                    <small>
                      {r.id} · v{r.version}.0
                    </small>
                    <ArrowRight size={14} />
                  </button>
                </div>
              </div>
            ))
          ) : (
            <Empty
              t={(en, ar) =>
                en === 'Nothing here yet'
                  ? t('No supporting source found', 'لم يتم العثور على مصدر داعم')
                  : t(
                      'Try a more specific topic, or index an approved document.',
                      'جرّب موضوعاً أدق أو فهرس وثيقة معتمدة.',
                    ) || t(en, ar)
              }
            />
          )}
          <small>
            {t(
              'Local prototype retrieval from document excerpts. No live AI service is connected.',
              'استرجاع محلي من مقتطفات الوثائق في النموذج. لا توجد خدمة ذكاء اصطناعي حية متصلة.',
            )}
          </small>
        </section>
      )}
      <div className="d-library-heading">
        <div>
          <p className="p-eyebrow">{t('VISUAL DOCUMENT DISCOVERY', 'اكتشاف مرئي للوثائق')}</p>
          <h3>
            {t('Approved knowledge library', 'مكتبة المعرفة المعتمدة')} <span>{rows.length}</span>
          </h3>
        </div>
        <div className="d-view-switch" aria-label={t('Results layout', 'تخطيط النتائج')}>
          <button
            aria-label={t('Thumbnail view', 'عرض المصغرات')}
            aria-pressed={view === 'grid'}
            onClick={() => setView('grid')}
          >
            <Grid2X2 size={17} />
          </button>
          <button
            aria-label={t('List view', 'عرض القائمة')}
            aria-pressed={view === 'list'}
            onClick={() => setView('list')}
          >
            <List size={17} />
          </button>
        </div>
      </div>
      <div className="d-search-toolbar">
        <div className="p-input-icon">
          <Search size={17} />
          <input
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            aria-label={t('Search published records', 'بحث السجلات المنشورة')}
            placeholder={t(
              'Search title, content, department or tracking number…',
              'ابحث بالعنوان أو المحتوى أو الإدارة أو رقم التتبع…',
            )}
          />
          {query && (
            <button
              className="p-icon"
              aria-label={t('Clear search', 'مسح البحث')}
              onClick={() => setQuery('')}
            >
              <X size={14} />
            </button>
          )}
        </div>
        <button className="p-btn" aria-expanded={filtersOpen} onClick={() => setFiltersOpen(!filtersOpen)}>
          <SlidersHorizontal size={15} />
          {t('Filters', 'المرشحات')}
          {activeFilters ? ` (${activeFilters})` : ''}
        </button>
        <button
          className="p-btn"
          disabled={!query.trim()}
          onClick={() => {
            setState((s) => ({ ...s, savedSearches: [...new Set([...s.savedSearches, query.trim()])] }))
            notify(t('Search saved.', 'تم حفظ البحث.'))
          }}
        >
          <BookmarkPlus size={15} />
          {t('Save search', 'حفظ البحث')}
        </button>
      </div>
      {filtersOpen && (
        <div className="d-filters">
          <label>
            {t('Document class', 'فئة الوثيقة')}
            <select
              aria-label={t('Class filter', 'تصفية الفئة')}
              value={kind}
              onChange={(e) => setKind(e.target.value)}
            >
              <option value="all">{t('All classes', 'كل الفئات')}</option>
              {state.settings.classes.map((v) => (
                <option value={v} key={v}>
                  {local(v, lang)}
                </option>
              ))}
            </select>
          </label>
          <label>
            {t('Department', 'الإدارة')}
            <select
              aria-label={t('Search department', 'إدارة البحث')}
              value={department}
              onChange={(e) => setDepartment(e.target.value)}
            >
              <option value="all">{t('All departments', 'كل الإدارات')}</option>
              {options.map((v) => (
                <option key={v} value={v}>
                  {local(v, lang)}
                </option>
              ))}
            </select>
          </label>
          <label>
            {t('Sensitivity', 'الحساسية')}
            <select
              aria-label={t('Sensitivity filter', 'تصفية الحساسية')}
              value={sensitivity}
              onChange={(e) => setSensitivity(e.target.value)}
            >
              <option value="all">{t('All sensitivities', 'كل درجات الحساسية')}</option>
              {['Public', 'Internal', 'Confidential', 'Secret'].map((v) => (
                <option key={v} value={v}>
                  {local(v, lang)}
                </option>
              ))}
            </select>
          </label>
          <button
            className="p-link"
            onClick={() => {
              setKind('all')
              setDepartment('all')
              setSensitivity('all')
            }}
          >
            {t('Reset filters', 'إعادة المرشحات')}
          </button>
        </div>
      )}
      {!!state.savedSearches.length && (
        <div className="d-prompts">
          {state.savedSearches.map((q) => (
            <button key={q} onClick={() => setQuery(q)}>
              <BookmarkPlus size={13} />
              {q}
            </button>
          ))}
        </div>
      )}
      {!rows.length ? (
        <Empty t={t} />
      ) : view === 'grid' ? (
        <div className="d-thumbnail-grid">
          {rows.map((record) => (
            <SourceCard key={record.id} record={record} lang={lang} t={t} onOpen={onOpen} />
          ))}
        </div>
      ) : (
        <div className="p-card no-pad">
          <DocumentTable rows={rows} lang={lang} t={t} onOpen={onOpen} selectedId={selectedId} />
        </div>
      )}
    </>
  )
}

type Message = { id: string; question: string; sourceIds: string[]; feedback?: 'up' | 'down' }
export function AssistantDock({
  visible,
  lang,
  t,
  onOpen,
  onSearch,
  context,
}: {
  visible: RecordItem[]
  lang: Language
  t: Translate
  onOpen: (r: RecordItem) => void
  onSearch: (q: string) => void
  context?: RecordItem
}) {
  const [open, setOpen] = useState(false)
  const [question, setQuestion] = useState('')
  const [messages, setMessages] = useState<Message[]>([])
  const input = useRef<HTMLInputElement>(null)
  const end = useRef<HTMLDivElement>(null)
  const launcher = useRef<HTMLButtonElement>(null)
  useEffect(() => {
    if (open) input.current?.focus()
  }, [open])
  useEffect(() => {
    end.current?.scrollIntoView({ block: 'nearest', behavior: 'smooth' })
  }, [messages])
  useEffect(() => {
    const shortcut = (e: KeyboardEvent) => {
      if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'j') {
        e.preventDefault()
        setOpen((v) => !v)
      }
    }
    window.addEventListener('keydown', shortcut)
    return () => window.removeEventListener('keydown', shortcut)
  }, [])
  const close = () => {
    setOpen(false)
    launcher.current?.focus()
  }
  const send = (value: string) => {
    if (!value.trim()) return
    setMessages((old) => [
      ...old,
      {
        id: crypto.randomUUID(),
        question: value.trim(),
        sourceIds: discover(visible, value)
          .slice(0, 3)
          .map((r) => r.id),
      },
    ])
    setQuestion('')
  }
  const available = visible.filter((r) => r.status === 'Published' && r.indexed)
  return (
    <div className="d-assistant-dock">
      {open && (
        <section
          className="d-assistant"
          role="dialog"
          aria-modal="false"
          aria-label={t('Docaya AI Assistant', 'مساعد دوكايا الذكي')}
          onKeyDown={(e) => {
            if (e.key === 'Escape') {
              e.stopPropagation()
              close()
            }
          }}
        >
          <header>
            <span className="d-assistant-mark">
              <DocayaAIMark size={32} />
            </span>
            <div>
              <strong>{t('Docaya AI Assistant', 'مساعد دوكايا الذكي')}</strong>
              <small>{t('Your document companion', 'رفيقك في معرفة الوثائق')}</small>
            </div>
            <button className="p-icon" aria-label={t('Minimize assistant', 'تصغير المساعد')} onClick={close}>
              <ChevronDown size={20} />
            </button>
          </header>
          <div className="d-assistant-scroll">
            {!messages.length && (
              <div className="d-assistant-welcome">
                <span>
                  <DocayaAIMark size={46} />
                </span>
                <h3>{t('A little help. A clearer next step.', 'مساعدة بسيطة. وخطوة أوضح.')}</h3>
                <p>
                  {t(
                    'Find a policy, explore a thumbnail, or ask a question. Every answer starts with an accessible source.',
                    'اعثر على سياسة أو استعرض وثيقة أو اطرح سؤالاً. كل إجابة تبدأ بمصدر متاح لك.',
                  )}
                </p>
                <div>
                  {[
                    ['Find road safety guidance', 'ابحث عن إرشادات السلامة المرورية'],
                    ['What are the retention rules?', 'ما قواعد الحفظ؟'],
                    ['Civil defence readiness', 'جاهزية الدفاع المدني'],
                  ].map(([en, ar]) => (
                    <button key={en} onClick={() => send(t(en, ar))}>
                      {t(en, ar)}
                      <ArrowRight size={14} />
                    </button>
                  ))}
                </div>
              </div>
            )}
            {context && (
              <div className="d-context-chip">
                <FileSearch size={15} />
                <span>
                  {t('In your workspace', 'في مساحة عملك')}:{' '}
                  {lang === 'ar' ? context.titleAr || context.title : context.title}
                </span>
                <button
                  aria-label={t('Find related published records', 'ابحث عن سجلات منشورة مرتبطة')}
                  onClick={() => send(context.department + ' ' + context.kind)}
                >
                  <Search size={14} />
                </button>
              </div>
            )}
            {messages.map((message) => {
              const sources = message.sourceIds
                .map((id) => available.find((r) => r.id === id))
                .filter((r): r is RecordItem => !!r)
              return (
                <div key={message.id} className="d-conversation">
                  <p className="d-user-message">{message.question}</p>
                  <div className="d-assistant-message">
                    <strong>
                      <DocayaAIMark size={25} />
                      {t('Here is what your records say', 'هذا ما تقوله سجلاتك')}
                    </strong>
                    {sources.length ? (
                      <>
                        <p>
                          {lang === 'ar' ? sources[0].summaryAr || sources[0].summary : sources[0].summary}
                        </p>
                        <small>
                          {sources.length} {t('supporting sources', 'مصادر داعمة')}
                        </small>
                        <div className="d-chat-sources">
                          {sources.map((record) => (
                            <SourceCard
                              key={record.id}
                              record={record}
                              lang={lang}
                              t={t}
                              compact
                              onOpen={(r) => {
                                onOpen(r)
                                close()
                              }}
                            />
                          ))}
                        </div>
                      </>
                    ) : (
                      <p>
                        {t(
                          'I could not find a supporting published source. Try a more specific topic or open the knowledge library.',
                          'لم أجد مصدراً منشوراً داعماً. جرّب موضوعاً أدق أو افتح مكتبة المعرفة.',
                        )}
                      </p>
                    )}
                    <div className="d-response-tools">
                      <button
                        className="p-link"
                        onClick={() => {
                          onSearch(message.question)
                          close()
                        }}
                      >
                        {t('Explore thumbnails', 'استكشف المصغرات')}
                        <ArrowRight size={13} />
                      </button>
                      <span />
                      <button
                        aria-label={t('Helpful answer', 'إجابة مفيدة')}
                        aria-pressed={message.feedback === 'up'}
                        onClick={() =>
                          setMessages((rows) =>
                            rows.map((m) => (m.id === message.id ? { ...m, feedback: 'up' } : m)),
                          )
                        }
                      >
                        <ThumbsUp size={14} />
                      </button>
                      <button
                        aria-label={t('Needs improvement', 'تحتاج تحسيناً')}
                        aria-pressed={message.feedback === 'down'}
                        onClick={() =>
                          setMessages((rows) =>
                            rows.map((m) => (m.id === message.id ? { ...m, feedback: 'down' } : m)),
                          )
                        }
                      >
                        <ThumbsDown size={14} />
                      </button>
                    </div>
                  </div>
                </div>
              )
            })}
            <div ref={end} />
          </div>
          <footer>
            <form
              onSubmit={(e) => {
                e.preventDefault()
                send(question)
              }}
            >
              <input
                ref={input}
                value={question}
                onChange={(e) => setQuestion(e.target.value)}
                placeholder={t('Ask your document companion…', 'اسأل رفيقك في الوثائق…')}
                aria-label={t('Message Docaya assistant', 'رسالة لمساعد دوكايا')}
              />
              <button disabled={!question.trim()} aria-label={t('Send question', 'إرسال السؤال')}>
                <ArrowRight size={17} />
              </button>
            </form>
            <div>
              <small>
                {t('Demo AI · cited local excerpts · no live model', 'ذكاء تجريبي · مقتطفات محلية موثقة')}
              </small>
              <button className="p-link" disabled={!messages.length} onClick={() => setMessages([])}>
                {t('Clear chat', 'مسح المحادثة')}
              </button>
            </div>
          </footer>
        </section>
      )}
      <button
        ref={launcher}
        className={`d-ai-launcher ${open ? 'is-open' : ''}`}
        onClick={() => setOpen(!open)}
        aria-label={t('Open Docaya AI Assistant', 'فتح مساعد دوكايا الذكي')}
        aria-expanded={open}
      >
        <span>
          <DocayaAIMark size={32} />
        </span>
        <div>
          <strong>{t('Ask Docaya', 'اسأل دوكايا')}</strong>
          <small>{t('AI Assistant', 'المساعد الذكي')}</small>
        </div>
        <kbd>⌘ J</kbd>
      </button>
    </div>
  )
}
