/**
 * Docaya client generation.
 *
 * The contract is the source of truth. Clients are generated from it and the
 * generation script is committed, never hand-edited output (TAD 17.3).
 *
 *   --target ts    TypeScript types into src/web/src/api/generated
 *   --target cs    C# client into src/api/Generated via NSwag
 *   --target all   both
 */

import { mkdir, rm } from 'node:fs/promises'
import { spawn } from 'node:child_process'
import { fileURLToPath } from 'node:url'
import path from 'node:path'

const here = path.dirname(fileURLToPath(import.meta.url))
const contractsRoot = path.resolve(here, '..')
const repoRoot = path.resolve(contractsRoot, '..', '..')

const OPENAPI_PATH = path.join(contractsRoot, 'openapi', 'docaya-api-v1.yaml')
const OPENAPI_TYPESCRIPT_CLI = path.join(repoRoot, 'node_modules', 'openapi-typescript', 'bin', 'cli.js')
const TS_OUTPUT_DIR = path.join(repoRoot, 'src', 'web', 'src', 'api', 'generated')
const TS_OUTPUT_FILE = path.join(TS_OUTPUT_DIR, 'docaya-api.ts')
const CS_OUTPUT_DIR = path.join(repoRoot, 'src', 'api', 'Generated')

const argv = process.argv.slice(2)
const targetIndex = argv.indexOf('--target')
const target = targetIndex >= 0 ? argv[targetIndex + 1] : 'all'

if (!['ts', 'cs', 'all'].includes(target)) {
  console.error(`Unknown target "${target}". Use ts, cs or all.`)
  process.exit(1)
}

/** Runs a command, inheriting stdio, and resolves with its exit code. */
function run(command, args, cwd) {
  return new Promise((resolve) => {
    const child = spawn(command, args, { cwd, stdio: 'inherit', shell: false })
    child.on('close', (code) => resolve(code ?? 1))
    child.on('error', () => resolve(1))
  })
}

async function generateTypeScript() {
  console.log('Generating TypeScript client -> src/web/src/api/generated')
  await rm(TS_OUTPUT_DIR, { recursive: true, force: true })
  await mkdir(TS_OUTPUT_DIR, { recursive: true })

  const code = await run(
    process.execPath,
    [OPENAPI_TYPESCRIPT_CLI, OPENAPI_PATH, '--output', TS_OUTPUT_FILE],
    contractsRoot,
  )

  if (code !== 0) {
    console.error('TypeScript client generation failed.')
    process.exit(code)
  }
}

async function generateCSharp() {
  console.log('Generating C# client -> src/api/Generated')
  await mkdir(CS_OUTPUT_DIR, { recursive: true })

  // NSwag is restored as a .NET local tool from src/api/.config/dotnet-tools.json.
  const code = await run(
    'dotnet',
    [
      'tool',
      'run',
      'nswag',
      'openapi2csclient',
      `/input:${OPENAPI_PATH}`,
      `/output:${path.join(CS_OUTPUT_DIR, 'DocayaApiClient.cs')}`,
      '/namespace:Docaya.Contracts.Generated',
      '/className:DocayaApiClient',
      '/generateClientInterfaces:true',
      '/generateOptionalParameters:true',
      '/useBaseUrl:false',
    ],
    path.join(repoRoot, 'src', 'api'),
  )

  if (code !== 0) {
    console.error('C# client generation failed. Run "dotnet tool restore" in src/api first.')
    process.exit(code)
  }
}

if (target === 'ts' || target === 'all') await generateTypeScript()
if (target === 'cs' || target === 'all') await generateCSharp()

console.log('Client generation complete.')
