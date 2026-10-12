[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('install', 'upgrade', 'rollback')][string]$Operation,
    [Parameter(Mandatory)][string]$ConfigurationFile,
    [Parameter(Mandatory)][string]$ReleaseDirectory,
    [string]$MigrationFile = ''
)
. "$PSScriptRoot/common.ps1"
$config = Read-JsonFile $ConfigurationFile
$manifest = Read-JsonFile (Join-Path $ReleaseDirectory 'release-manifest.json')
$steps = @(
    'Validate target configuration, release checksums and unresolved readiness blockers',
    'Verify authenticated Azure tenant/subscription and availability of the immutable image in target ACR',
    'Require reviewed subscription-scope what-if evidence before execution',
    'Apply the selected release ARM template with the target parameter file'
)
if ($Operation -eq 'install') { $steps += 'Run the canonical database master exactly once, including its 01-15 SQLCMD includes' }
if ($Operation -eq 'upgrade') { $steps += 'Run the explicitly supplied versioned migration, or perform a schema-compatible application-only upgrade' }
if ($Operation -eq 'rollback') { $steps += 'Require database backward-compatibility evidence; never run down-migrations automatically' }
$steps += @('Deploy the selected Functions ZIP and static web bundle', 'Run resource and HTTP checks; retain results and release identity')
[ordered]@{
    operation = $Operation; mode = 'PLAN_ONLY'; environment = $config.environment
    releaseVersion = $manifest.version; releaseStatus = $manifest.status
    configurationFile = [IO.Path]::GetFullPath($ConfigurationFile)
    releaseDirectory = [IO.Path]::GetFullPath($ReleaseDirectory)
    migrationFile = $MigrationFile; steps = $steps
    prerequisites = @(
        'Target tenant app registrations, scope/roles/consent and SharePoint Sites.Selected grants completed',
        'Private-network runner reaches SQL, ACR, API gateway and Functions SCM endpoint',
        'ACR exists and contains docaya-api at the configured digest; blank-subscription bootstrap remains blocked',
        'Client configuration, Search schema and Power BI provisioning completed',
        'Signed release verification and security/rollback rehearsal evidence reviewed'
    )
} | ConvertTo-Json -Depth 6
