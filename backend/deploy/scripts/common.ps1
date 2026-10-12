Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:RepositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))

function Invoke-Checked {
    param([Parameter(Mandatory)][string]$Command, [string[]]$Arguments = @())
    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Command failed with exit code $LASTEXITCODE." }
}

function Read-JsonFile {
    param([Parameter(Mandatory)][string]$Path)
    Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Get-ContainedPath {
    param([string]$Root, [string]$RelativePath)
    $base = [IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    if ([IO.Path]::IsPathRooted($RelativePath)) { throw 'Artifact paths must be relative.' }
    $candidate = [IO.Path]::GetFullPath((Join-Path $base $RelativePath))
    if (-not $candidate.StartsWith($base + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Artifact path escapes release directory: $RelativePath"
    }
    return $candidate
}

function Assert-TargetConfiguration {
    param($Configuration)
    foreach ($key in @('tenantId', 'subscriptionId', 'apiApplicationId')) {
        $value = [guid]::Empty
        if (-not [guid]::TryParse([string]$Configuration.$key, [ref]$value) -or $value -eq [guid]::Empty) {
            throw "Configure a valid $key before execution."
        }
    }
    if ($Configuration.environment -notin @('dev', 'test', 'prod')) { throw 'Invalid environment.' }
    foreach ($key in @('location', 'resourceGroupName', 'registryName', 'functionAppName', 'staticWebAppName', 'sqlServer', 'sqlDatabase', 'parameterFile')) {
        if ([string]::IsNullOrWhiteSpace([string]$Configuration.$key)) { throw "Configure $key before execution." }
    }
    if ($Configuration.apiImageDigest -cnotmatch '^sha256:[a-f0-9]{64}$') { throw 'An immutable API image digest is required.' }
    foreach ($key in @('publicBaseUrl', 'apiBaseUrl')) {
        $uri = $null
        if (-not [uri]::TryCreate([string]$Configuration.$key, [UriKind]::Absolute, [ref]$uri) -or $uri.Scheme -ne 'https') {
            throw "$key must be an HTTPS URL."
        }
    }
    if (-not (Test-Path -LiteralPath $Configuration.parameterFile -PathType Leaf)) { throw 'Target ARM JSON parameter file does not exist.' }
    $parameters = Read-JsonFile $Configuration.parameterFile
    foreach ($entry in @{ environmentName = $Configuration.environment; location = $Configuration.location; apiImageDigest = $Configuration.apiImageDigest; entraTenantId = $Configuration.tenantId }.GetEnumerator()) {
        if ([string]$parameters.parameters.($entry.Key).value -ne [string]$entry.Value) { throw "Parameter/configuration mismatch: $($entry.Key)" }
    }
    $expectedGroup = "rg-docaya-$($Configuration.environment)-$($Configuration.location)"
    if ($Configuration.resourceGroupName -ne $expectedGroup) { throw "Template resource group must be $expectedGroup." }
}

function Assert-AzureContext {
    param($Configuration)
    $accountText = Invoke-Checked az @('account', 'show', '--output', 'json', '--only-show-errors')
    $account = ($accountText -join "`n") | ConvertFrom-Json
    if ($account.id -ne $Configuration.subscriptionId -or $account.tenantId -ne $Configuration.tenantId) {
        throw 'Azure CLI tenant/subscription differs from the target. Select the intended account explicitly before execution.'
    }
}

function Assert-Release {
    param([string]$ReleaseDirectory)
    $manifest = Read-JsonFile (Join-Path $ReleaseDirectory 'release-manifest.json')
    if ($manifest.status -ne 'CANDIDATE') { throw "Release is $($manifest.status); unresolved implementation or verification blockers prohibit execution." }
    if ($manifest.sourceOnly) { throw 'A source-only package cannot be executed.' }
    if ($manifest.apiImageDigest -cnotmatch '^sha256:[a-f0-9]{64}$') { throw 'Release manifest lacks a valid image digest.' }
    if (@($manifest.files).Count -eq 0) { throw 'Release manifest contains no files.' }
    foreach ($file in $manifest.files) {
        $filePath = Get-ContainedPath $ReleaseDirectory $file.path
        if (-not (Test-Path -LiteralPath $filePath -PathType Leaf)) { throw "Missing release artifact: $($file.path)" }
        if ((Get-FileHash -LiteralPath $filePath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $file.sha256) {
            throw "Release artifact checksum mismatch: $($file.path)"
        }
    }
    foreach ($required in @('infra/main.json', 'web/index.html', 'functions.zip', 'sql/00_master_deploy.sql', 'readiness.json')) {
        if ($required -notin @($manifest.files.path)) { throw "Required artifact is not covered by manifest: $required" }
    }
    $readiness = Read-JsonFile (Join-Path $ReleaseDirectory 'readiness.json')
    if ($readiness.status -ne 'STATIC_CHECKS_PASSED' -or @($readiness.findings).Count -gt 0) { throw 'Release source readiness check did not pass.' }
    return $manifest
}
