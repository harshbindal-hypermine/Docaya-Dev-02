<# Local release assembly. Does not authenticate, deploy, push images or run SQL. #>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$OutputDirectory,
    [string]$ApiImageDigest = '',
    [switch]$SourceOnly
)
. "$PSScriptRoot/common.ps1"
if (-not $SourceOnly -and $ApiImageDigest -cnotmatch '^sha256:[a-f0-9]{64}$') { throw 'A full candidate requires the digest of the separately built/scanned API image.' }
$output = [IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path -LiteralPath $output) { throw 'Choose a new output directory; existing artifacts are never overwritten.' }
New-Item -ItemType Directory -Path $output | Out-Null
$status = 'BLOCKED'
Push-Location $script:RepositoryRoot
try {
    & node deploy/scripts/check-readiness.mjs --output (Join-Path $output 'readiness.json')
    $readinessCode = $LASTEXITCODE
    if (-not (Test-Path (Join-Path $output 'readiness.json'))) { throw 'Readiness inspection failed before producing a report. Run npm ci first.' }
    $version = (Read-JsonFile 'package.json').version
    foreach ($directory in @('infra', 'contracts', 'sql', 'deploy')) {
        New-Item -ItemType Directory -Path (Join-Path $output $directory) | Out-Null
    }
    Copy-Item -Path 'src/contracts/openapi', 'src/contracts/events' -Destination (Join-Path $output 'contracts') -Recurse
    # Keep the source location used by Bicep's loadTextContent, so source templates remain rebuildable.
    New-Item -ItemType Directory -Path (Join-Path $output 'src/contracts') -Force | Out-Null
    Copy-Item 'src/contracts/openapi' (Join-Path $output 'src/contracts') -Recurse
    # Snapshot the current tracked and untracked source, excluding ignored build/dependency folders.
    $sourceFiles = Invoke-Checked git @('ls-files', '--cached', '--others', '--exclude-standard', '--', 'src', 'infra', 'deploy', 'tests', 'scripts', '.github/workflows', 'global.json', 'Directory.Build.props', 'Directory.Packages.props', 'package.json', 'package-lock.json', 'README.md', 'playwright.config.ts')
    foreach ($sourceFile in $sourceFiles) {
        # A release must not capture private target configuration, even if untracked.
        if ($sourceFile -match '\.local\.(json|ya?ml)$') { continue }
        if ($sourceFile -like 'deploy/config/*' -and $sourceFile -notlike '*.example.json') { continue }
        if (-not (Test-Path -LiteralPath $sourceFile -PathType Leaf)) { continue }
        $destination = Get-ContainedPath $output $sourceFile
        New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
        Copy-Item -LiteralPath $sourceFile -Destination $destination -Force
    }
    $sqlRoot = 'docs/sol doc/Docaya-Database-Package-v1.3/Docaya-Database-Package-v1.3/sql'
    Copy-Item -Path "$sqlRoot/*.sql" -Destination (Join-Path $output 'sql')
    if (-not $SourceOnly) {
        Invoke-Checked npm @('run', 'contracts:validate')
        Invoke-Checked npm @('run', 'lint')
        Invoke-Checked npm @('run', 'test:unit')
        Invoke-Checked npm @('run', 'build')
        Invoke-Checked dotnet @('test', 'src/api/Docaya.Api.sln', '--configuration', 'Release')
        Invoke-Checked dotnet @('test', 'src/functions/Docaya.Functions.sln', '--configuration', 'Release')
        & ./infra/tests/validate-template.ps1
        Invoke-Checked az @('bicep', 'build', '--file', 'infra/main.bicep', '--outfile', (Join-Path $output 'infra/main.json'))
        Copy-Item 'src/web/dist' (Join-Path $output 'web') -Recurse
        $functionOutput = Join-Path $output 'functions'
        Invoke-Checked dotnet @('publish', 'src/functions/Docaya.Functions.csproj', '--configuration', 'Release', '--output', $functionOutput)
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [IO.Compression.ZipFile]::CreateFromDirectory($functionOutput, (Join-Path $output 'functions.zip'))
        if ($readinessCode -eq 0) { $status = 'CANDIDATE' }
    }
    $sourceCommit = (Invoke-Checked git @('rev-parse', 'HEAD') | Out-String).Trim()
    $dirty = @(& git status --porcelain).Count -gt 0
    $files = @(Get-ChildItem -LiteralPath $output -File -Recurse | Sort-Object FullName | ForEach-Object {
        [ordered]@{ path = $_.FullName.Substring($output.TrimEnd('\', '/').Length + 1).Replace('\', '/'); sha256 = (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant() }
    })
    [ordered]@{
        schemaVersion = 1; version = $version; status = $status; sourceOnly = [bool]$SourceOnly
        sourceCommit = $sourceCommit; workingTreeModified = $dirty; createdAtUtc = [DateTime]::UtcNow.ToString('o')
        apiImageDigest = $ApiImageDigest
        integrity = 'SHA-256 checksums only; not a cryptographic release signature'
        files = $files
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $output 'release-manifest.json') -Encoding UTF8
    Write-Host "Prepared $status local package: $output"
    if ($SourceOnly) { Write-Host 'Source review package only. No web/Functions/API release binaries have been certified.' }
}
finally { Pop-Location }
