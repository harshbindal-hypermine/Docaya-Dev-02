<# Offline regression tests. Azure, SWA and SQL calls are replaced with local functions. #>
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
. "$root/deploy/scripts/common.ps1"
$testRoot = Join-Path $root ("artifacts/script-tests/" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
$script:passes = 0
function Assert-Test([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "FAIL: $Message" }
    $script:passes++
}
function Assert-Throws([scriptblock]$Action, [string]$Pattern) {
    $caught = $null
    try { & $Action | Out-Null } catch { $caught = $_.Exception.Message }
    Assert-Test ($null -ne $caught -and $caught -match $Pattern) "Expected error matching '$Pattern'; received '$caught'."
}
function global:az { throw 'Unexpected Azure invocation in offline test.' }
function global:swa { throw 'Unexpected SWA invocation in offline test.' }
function global:sqlcmd { throw 'Unexpected SQL invocation in offline test.' }

Get-ChildItem "$root/deploy/scripts/*.ps1" | ForEach-Object {
    $tokens = $null; $parseErrors = $null
    $null = [Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$parseErrors)
    Assert-Test (@($parseErrors).Count -eq 0) "$($_.Name) parses"
}
$release = Join-Path $testRoot 'release'
New-Item -ItemType Directory -Path $release | Out-Null
$manifestPath = Join-Path $release 'release-manifest.json'
'{"status":"BLOCKED","version":"1.3.0"}' | Set-Content $manifestPath
$configFile = Join-Path $root 'deploy/config/environment.example.json'
foreach ($operation in @('install', 'upgrade', 'rollback')) {
    $plan = (& "$root/deploy/scripts/$operation.ps1" -ConfigurationFile $configFile -ReleaseDirectory $release | Out-String) | ConvertFrom-Json
    Assert-Test ($plan.mode -eq 'PLAN_ONLY' -and $plan.operation -eq $operation) "$operation defaults to a local plan"
    Assert-Throws { & "$root/deploy/scripts/$operation.ps1" -ConfigurationFile $configFile -ReleaseDirectory $release -Execute } 'Release is BLOCKED'
}
$tenantPlan = (& "$root/deploy/scripts/tenant-bootstrap.ps1" -ConfigurationFile $configFile | Out-String) | ConvertFrom-Json
Assert-Test ($tenantPlan.mode -eq 'PLAN_ONLY') 'Tenant bootstrap defaults to plan without Azure access'
Assert-Throws { Get-ContainedPath $release '../outside.json' } 'escapes'
Assert-Throws { Invoke-Checked node @('-e', 'process.exit(7)') } 'exit code 7'

# Construct a test candidate to verify the integrity gate, then alter an artifact.
foreach ($relative in @('infra/main.json', 'web/index.html', 'functions.zip', 'sql/00_master_deploy.sql')) {
    $destination = Get-ContainedPath $release $relative
    New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
    'test fixture' | Set-Content -LiteralPath $destination
}
'{"status":"STATIC_CHECKS_PASSED","findings":[]}' | Set-Content (Join-Path $release 'readiness.json')
$fileList = @(Get-ChildItem $release -Recurse -File | Where-Object { $_.Name -ne 'release-manifest.json' } | ForEach-Object {
    @{ path = $_.FullName.Substring($release.Length + 1).Replace('\', '/'); sha256 = (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant() }
})
$manifest = @{ status='CANDIDATE'; sourceOnly=$false; version='1.3.0'; apiImageDigest=('sha256:' + ('a' * 64)); files=$fileList }
$manifest | ConvertTo-Json -Depth 6 | Set-Content $manifestPath
$null = Assert-Release $release
Assert-Test $true 'Valid fixture passes local integrity gate'
'changed' | Set-Content (Join-Path $release 'web/index.html')
Assert-Throws { Assert-Release $release } 'checksum mismatch'
$manifest.sourceOnly = $true
$manifest | ConvertTo-Json -Depth 6 | Set-Content $manifestPath
Assert-Throws { Assert-Release $release } 'source-only'

# Database plan must select the master, not run both the master and its included files.
$databasePlan = (& "$root/deploy/scripts/migrate-database.ps1" -ConfigurationFile $configFile -SqlDirectory (Join-Path $release 'sql') | Out-String) | ConvertFrom-Json
Assert-Test ($databasePlan.mode -eq 'PLAN_ONLY' -and $databasePlan.inputFile.EndsWith('00_master_deploy.sql')) 'Database plan selects one master'
Assert-Throws { & "$root/deploy/scripts/migrate-database.ps1" -ConfigurationFile $configFile -SqlDirectory (Join-Path $release 'sql') -MigrationFile 'other.sql' } 'exactly one'

# Verify SQL arguments and target isolation with mocks, including native failure propagation.
$config = Read-JsonFile $configFile
$config.tenantId = '11111111-1111-1111-1111-111111111111'
$config.subscriptionId = '22222222-2222-2222-2222-222222222222'
$config.apiApplicationId = '33333333-3333-3333-3333-333333333333'
$config.apiImageDigest = 'sha256:' + ('a' * 64)
$config.registryName = 'testregistry'
$config.functionAppName = 'testfunctions'
$config.staticWebAppName = 'testweb'
$config.sqlServer = 'test.database.windows.net'
$config.publicBaseUrl = 'https://web.example.invalid'
$config.apiBaseUrl = 'https://api.example.invalid'
$config.parameterFile = Join-Path $testRoot 'parameters.json'
@{ parameters = @{
    environmentName = @{ value = $config.environment }; location = @{ value = $config.location }
    apiImageDigest = @{ value = $config.apiImageDigest }; entraTenantId = @{ value = $config.tenantId }
} } | ConvertTo-Json -Depth 5 | Set-Content $config.parameterFile
foreach ($property in $config.sqlIdentities.PSObject.Properties) { $property.Value = 'id-' + $property.Name }
$validConfigFile = Join-Path $testRoot 'configuration.json'
$config | ConvertTo-Json -Depth 5 | Set-Content $validConfigFile
$global:SqlTestCalls = @()
function global:az {
    $global:LASTEXITCODE = 0
    '{"tenantId":"11111111-1111-1111-1111-111111111111","id":"22222222-2222-2222-2222-222222222222"}'
}
function global:sqlcmd { $global:SqlTestCalls += ,@($args); $global:LASTEXITCODE = 0 }
& "$root/deploy/scripts/migrate-database.ps1" -ConfigurationFile $validConfigFile -SqlDirectory (Join-Path $release 'sql') -Execute
Assert-Test ($global:SqlTestCalls.Count -eq 1) 'Database runner invokes SQLCMD exactly once'
$sqlArguments = $global:SqlTestCalls[0]
Assert-Test ('-G' -in $sqlArguments -and '-N' -in $sqlArguments -and '-b' -in $sqlArguments) 'Database runner uses Entra, encryption and stop-on-error'
Assert-Test (@($sqlArguments | Where-Object { $_ -match 'Identity=id-' }).Count -eq 6) 'All six SQL identity variables are passed'
Assert-Test ($sqlArguments[$sqlArguments.IndexOf('-i') + 1].EndsWith('00_master_deploy.sql')) 'Master is the only SQL input'
$config.sqlIdentities.ApiIdentity = "unsafe'identity"
$config | ConvertTo-Json -Depth 5 | Set-Content $validConfigFile
Assert-Throws { & "$root/deploy/scripts/migrate-database.ps1" -ConfigurationFile $validConfigFile -SqlDirectory (Join-Path $release 'sql') -Execute } 'managed-identity name'
Assert-Test ($global:SqlTestCalls.Count -eq 1) 'Unsafe SQLCMD substitution never reaches SQL'
$config.sqlIdentities.ApiIdentity = 'id-api'
$config | ConvertTo-Json -Depth 5 | Set-Content $validConfigFile
function global:sqlcmd { $global:LASTEXITCODE = 3 }
Assert-Throws { & "$root/deploy/scripts/migrate-database.ps1" -ConfigurationFile $validConfigFile -SqlDirectory (Join-Path $release 'sql') -Execute } 'exit code 3'
function global:az { $global:LASTEXITCODE = 0; '{"tenantId":"different","id":"different"}' }
Assert-Throws { & "$root/deploy/scripts/migrate-database.ps1" -ConfigurationFile $validConfigFile -SqlDirectory (Join-Path $release 'sql') -Execute } 'differs from the target'

Write-Host "$script:passes offline deployment-script assertions passed. No cloud or database commands executed."
