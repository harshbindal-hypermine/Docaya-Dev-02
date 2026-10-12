import type { RecordItem } from './model'

const stopWords = new Set([
  'what',
  'which',
  'where',
  'how',
  'the',
  'are',
  'for',
  'does',
  'can',
  'about',
  'find',
  'show',
  'documents',
  'document',
  'please',
  'with',
  'from',
  'ماذا',
  'كيف',
  'اين',
  'عن',
  'ما',
  'الوثائق',
  'اعرض',
  'ابحث',
])
export function normalizeText(value: string) {
  return value
    .toLowerCase()
    .normalize('NFKD')
    .replace(/[\u064B-\u065F\u0670]/g, '')
    .replace(/[أإآ]/g, 'ا')
    .replace(/ى/g, 'ي')
    .replace(/[^\p{L}\p{N}\s-]/gu, ' ')
    .replace(/\s+/g, ' ')
    .trim()
}
export function discover(records: RecordItem[], query: string) {
  const tokens = normalizeText(query)
    .split(' ')
    .filter((token) => token.length > 1 && !stopWords.has(token))
  const rows = records.filter((r) => r.status === 'Published' && r.indexed)
  if (!query.trim()) return rows
  if (!tokens.length) return []
  return rows
    .map((record) => {
      const title = normalizeText(`${record.title} ${record.titleAr} ${record.id} ${record.kind}`)
      const content = normalizeText(
        `${record.summary} ${record.summaryAr} ${record.department} ${record.reference}`,
      )
      return {
        record,
        score: tokens.reduce(
          (score, token) => score + (title.includes(token) ? 3 : content.includes(token) ? 1 : 0),
          0,
        ),
      }
    })
    .filter((item) => item.score > 0)
    .sort((a, b) => b.score - a.score)
    .map((item) => item.record)
}
