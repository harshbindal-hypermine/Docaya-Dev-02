<# SQLCMD Entra authentication; master includes are executed once, never master plus each child. #>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ConfigurationFile,
    [string]$SqlDirectory = '',
    [string]$MigrationFile = '',
    [switch]$Execute
)
. "$PSScriptRoot/common.ps1"
if ([bool]$SqlDirectory -eq [bool]$MigrationFile) { throw 'Supply exactly one of SqlDirectory or MigrationFile.' }
$config = Read-JsonFile $ConfigurationFile
$inputFile = if ($MigrationFile) { [IO.Path]::GetFullPath($MigrationFile) } else { [IO.Path]::GetFullPath((Join-Path $SqlDirectory '00_master_deploy.sql')) }
if (-not (Test-Path -LiteralPath $inputFile -PathType Leaf)) { throw 'SQL input file is missing.' }
if (-not $Execute) {
    [ordered]@{ mode = 'PLAN_ONLY'; inputFile = $inputFile; database = $config.sqlDatabase; server = $config.sqlServer; authentication = 'Entra via sqlcmd -G'; rollback = 'No automatic down-migration; require isolated rehearsal and recovery evidence' } | ConvertTo-Json
    return
}
Assert-TargetConfiguration $config
Assert-AzureContext $config
$sqlVariables = @()
if ($SqlDirectory) {
    foreach ($name in @('ApiIdentity', 'CaptureIdentity', 'PromotionIdentity', 'WorkflowIdentity', 'IndexingIdentity', 'AnalyticsIdentity')) {
        $value = [string]$config.sqlIdentities.$name
        # SQLCMD substitution occurs inside SQL literals; reject quotes and metacharacters.
        if ($value -notmatch '^[A-Za-z0-9_-]{1,128}$') { throw "Configure the managed-identity name for sqlIdentities.$name." }
        $sqlVariables += "$name=$value"
    }
}
Push-Location (Split-Path -Parent $inputFile)
try {
    $arguments = @('-S', "tcp:$($config.sqlServer),1433", '-d', $config.sqlDatabase, '-G', '-N', '-I', '-b', '-r', '1', '-i', $inputFile)
    if ($sqlVariables.Count -gt 0) { $arguments += '-v'; $arguments += $sqlVariables }
    Invoke-Checked sqlcmd $arguments
}
finally { Pop-Location }
