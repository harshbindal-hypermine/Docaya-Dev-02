// Local inspection only. Never authenticates to, or changes, an external service.
import { readFile, readdir, mkdir, writeFile, access } from 'node:fs/promises'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { createRequire } from 'node:module'

const YAML = createRequire(new URL('../../src/contracts/package.json', import.meta.url))('yaml')

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..')
const args = process.argv.slice(2)
const reportIndex = args.indexOf('--output')
const output = reportIndex >= 0 ? args[reportIndex + 1] : undefined
if (reportIndex >= 0 && (!output || output.startsWith('--'))) throw new Error('--output needs a file path')
const findings = []
const read = (relative) => readFile(path.join(root, relative), 'utf8')
async function files(dir, extension) {
  const entries = await readdir(path.join(root, dir), { withFileTypes: true })
  const result = []
  for (const e of entries) {
    if (['bin', 'obj', 'node_modules', 'dist', 'Generated'].includes(e.name)) continue
    const name = `${dir}/${e.name}`
    if (e.isDirectory()) result.push(...(await files(name, extension)))
    else if (name.endsWith(extension)) result.push(name)
  }
  return result
}
function fail(id, message, evidence) {
  findings.push({ id, message, evidence })
}
for (const file of await files('src/functions', '.cs')) {
  const text = await read(file)
  text.split(/\r?\n/).forEach((line, index) => {
    if (/throw new NotImplementedException/.test(line))
      fail('WORKER_STUB', 'Worker throws NotImplementedException', `${file}:${index + 1}`)
  })
}
const contract = YAML.parse(await read('src/contracts/openapi/docaya-api-v1.yaml'))
const endpointSource = (await Promise.all((await files('src/api/Docaya.Api', '.cs')).map(read))).join('\n')
const operations = Object.values(contract.paths).flatMap((item) =>
  Object.entries(item)
    .filter(([method]) => ['get', 'post', 'put', 'patch', 'delete', 'head', 'options'].includes(method))
    .map(([, operation]) => operation.operationId),
)
// Contract names are a useful gap check, not proof of endpoint semantics or authorization.
for (const operation of operations) {
  if (!endpointSource.includes(`"${operation}"`))
    fail('API_OPERATION', `No named API endpoint found for ${operation}`, 'src/api/Docaya.Api')
}
if (/from ['"].*prototype\/PrototypeApp['"]/.test(await read('src/web/src/main.tsx'))) {
  fail('PROTOTYPE_ENTRY', 'Production build entry point loads the browser prototype', 'src/web/src/main.tsx')
}
for (const name of [
  'install',
  'upgrade',
  'rollback',
  'validate',
  'tenant-bootstrap',
  'prepare-release',
  'migrate-database',
]) {
  try {
    await access(path.join(root, `deploy/scripts/${name}.ps1`))
  } catch {
    fail('MISSING_SCRIPT', `Missing ${name}.ps1`, 'deploy/scripts')
  }
}
const ports = (await files('src/api/Docaya.Application/Ports', '.cs')).map((f) => path.basename(f, '.cs'))
const infrastructure = (
  await Promise.all((await files('src/api/Docaya.Infrastructure', '.cs')).map(read))
).join('\n')
for (const port of ports) {
  if (!new RegExp(`class\\s+\\w+[^{}]*:\\s*[^{}]*\\b${port}\\b`).test(infrastructure)) {
    fail('ADAPTER_MISSING', `No concrete class found implementing ${port}`, 'src/api/Docaya.Infrastructure')
  }
}
const blockers = JSON.parse(await read('deploy/readiness-blockers.json'))
for (const item of blockers.items) {
  if (item.status !== 'resolved') fail(item.id, item.detail, item.evidence)
  else {
    const proof = path.resolve(root, item.verification || '.')
    if (!item.verification || !proof.startsWith(root + path.sep))
      fail(item.id, 'Resolution needs a repository-local verification artifact', item.evidence)
    else {
      try {
        await access(proof)
      } catch {
        fail(item.id, 'Resolution verification artifact is missing', item.verification)
      }
    }
  }
}
const report = {
  checkedAtUtc: new Date().toISOString(),
  status: findings.length ? 'BLOCKED' : 'STATIC_CHECKS_PASSED',
  scope: 'Local source completeness only; not deployment, security or functional certification',
  contractOperations: operations.length,
  findings,
}
if (output) {
  await mkdir(path.dirname(path.resolve(output)), { recursive: true })
  await writeFile(output, JSON.stringify(report, null, 2) + '\n')
}
console.log(JSON.stringify(report, null, 2))
process.exitCode = findings.length ? 1 : 0
