import type { RecordItem } from './model'

export type SuggestedFields = Pick<
  RecordItem,
  'title' | 'kind' | 'department' | 'sensitivity' | 'flow' | 'summary'
>
export type ClassificationSuggestion = {
  values: SuggestedFields
  confidence: number
  source: 'filename' | 'filename-and-text'
  reasons: { en: string; ar: string }[]
}
type ClassifyOptions = { classes: string[]; departments: string[]; defaultDepartment: string }

/** Deterministic workshop suggestions, not a model or an authority for access decisions. */
export function suggestClassification(
  filename: string,
  text: string,
  options: ClassifyOptions,
): ClassificationSuggestion {
  const title = filename
    .replace(/\.[^.]+$/, '')
    .replace(/[_-]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
  const excerpt = [...text.slice(0, 12000)]
    .filter((character) => character.charCodeAt(0) >= 32 || ['\n', '\r', '\t'].includes(character))
    .join('')
  const haystack = `${title}\n${excerpt}`.toLowerCase()
  const reasons: ClassificationSuggestion['reasons'] = []
  let kind = ''
  const classRules: [RegExp, string[]][] = [
    [/policy|governance|سياسة|حوكمة/, ['Policy']],
    [/procedure|protocol|\bsop\b|إجراء|إجراءات|بروتوكول/, ['Procedure', 'Report']],
    [/standard|معيار/, ['Standard', 'Policy']],
    [/contract|agreement|عقد|اتفاقية/, ['Contract']],
    [/circular|تعميم/, ['Circular']],
    [/memo|memorandum|مذكرة/, ['Memo']],
    [/employee|onboarding|payroll|موظف|رواتب/, ['HR Record']],
    [/correspondence|letter|مراسلة|خطاب/, ['Correspondence']],
    [/report|assessment|inspection|تقرير|تقييم|تفتيش/, ['Report']],
  ]
  const classMatch =
    classRules.find(([rule]) => rule.test(title.toLowerCase())) ||
    classRules.find(([rule]) => rule.test(haystack))
  if (classMatch) {
    kind = classMatch[1].find((candidate) => options.classes.includes(candidate)) || ''
    if (kind)
      reasons.push({
        en: 'Document wording matched a configured document class.',
        ar: 'تطابقت كلمات الوثيقة مع إحدى فئات الوثائق المحددة.',
      })
  }
  const departmentRules: [RegExp, string][] = [
    [/civil defen[cs]e|fire|evacuation|دفاع مدني|الدفاع المدني|حريق|إخلاء/, 'Civil Defence'],
    [/traffic|patrol|road safety|مرور|دوريات|سلامة الطرق/, 'Traffic & Patrols'],
    [/forensic|evidence|chain of custody|أدلة|جنائية|الطب الشرعي/, 'Forensic Sciences'],
    [/residency|passport|identity|إقامة|الإقامة|جواز|هوية/, 'Residency & Identity'],
    [/governance|strategy|minister|حوكمة|استراتيجية|وزاري/, 'Strategy & Governance'],
    [/finance|budget|procurement|supplier|مالية|ميزانية|مشتريات/, 'Finance'],
    [/employee|human resources|onboarding|payroll|موظف|موارد بشرية|رواتب/, 'Human Resources'],
    [/legal|litigation|قانون|تقاضي/, 'Legal'],
  ]
  const departmentMatch = departmentRules.find(
    ([rule, value]) => rule.test(haystack) && options.departments.includes(value),
  )
  const department = departmentMatch?.[1] || options.defaultDepartment
  if (departmentMatch)
    reasons.push({
      en: `Topic keywords suggest ${department}.`,
      ar: 'تشير الكلمات المتعلقة بالموضوع إلى الإدارة المقترحة.',
    })
  let sensitivity: RecordItem['sensitivity'] = 'Internal'
  if (/\b(top secret|secret)\b|سري للغاية|سري جدا/.test(haystack)) sensitivity = 'Secret'
  else if (
    /\b(confidential|restricted|evidence|forensic|personal|contract|passport|payroll)\b|سري|أدلة|جنائية|بيانات شخصية|جواز|رواتب/.test(
      haystack,
    )
  )
    sensitivity = 'Confidential'
  else if (/\b(public|awareness|press release)\b|للجمهور|توعية|بيان صحفي/.test(haystack))
    sensitivity = 'Public'
  reasons.push(
    sensitivity === 'Internal'
      ? {
          en: 'Internal is a provisional default; confirm the sensitivity before submission.',
          ar: 'درجة «داخلي» افتراضية مؤقتة؛ تحقق من الحساسية قبل الإرسال.',
        }
      : {
          en: 'Sensitivity follows the strongest matching label or content cue; review it before sharing.',
          ar: 'تستند الحساسية إلى أقوى مؤشر في النص؛ راجعها قبل المشاركة.',
        },
  )
  const flow: RecordItem['flow'] =
    sensitivity === 'Secret'
      ? 'Conditional'
      : sensitivity === 'Confidential'
        ? 'Sequential'
        : /joint|interdepartmental|مشترك|بين الإدارات/.test(haystack)
          ? 'Parallel'
          : 'Single'
  const contentLines = excerpt
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line && !/^(DOCAYA SAMPLE|SYNTHETIC|DEMO ONLY)/i.test(line))
  const summary =
    contentLines.join(' ').slice(0, 420) ||
    `${title || 'Untitled document'}. ${department} document awaiting metadata review and approval.`
  const confidence = Math.min(
    96,
    42 +
      (classMatch && kind ? 19 : 0) +
      (departmentMatch ? 18 : 0) +
      (excerpt.trim() ? 10 : 0) +
      (sensitivity !== 'Internal' ? 7 : 0),
  )
  return {
    values: { title, kind, department, sensitivity, flow, summary },
    confidence,
    source: excerpt.trim() ? 'filename-and-text' : 'filename',
    reasons,
  }
}

/** Apply only untouched fields so recapture cannot erase an operator's corrections. */
export function applyClassification(
  record: RecordItem,
  suggestion: ClassificationSuggestion,
  protectedFields: ReadonlySet<keyof RecordItem>,
): RecordItem {
  const next = { ...record }
  for (const key of Object.keys(suggestion.values) as (keyof SuggestedFields)[]) {
    if (!protectedFields.has(key)) Object.assign(next, { [key]: suggestion.values[key] })
  }
  return next
}
