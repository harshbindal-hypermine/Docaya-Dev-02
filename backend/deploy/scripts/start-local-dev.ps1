param(
    [string]$SqlPassword = $env:DOCAYA_LOCAL_SQL_PASSWORD,
    [switch]$SkipContracts,
    [switch]$SkipSql,
    [switch]$SkipServiceBus,
    [switch]$SkipFunctions,
    [switch]$SkipWeb
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$apiProject = Join-Path $repositoryRoot 'src/api/Docaya.Api/Docaya.Api.csproj'
$functionsRoot = Join-Path $repositoryRoot 'src/functions'
$functionsSettings = Join-Path $functionsRoot 'local.settings.json'
$functionsSettingsTemplate = Join-Path $functionsRoot 'local.settings.example.json'

function Assert-Command {
    param([Parameter(Mandatory)][string]$Name)

    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command '$Name' was not found. Install it before starting the local dev stack."
    }
}

function Invoke-Checked {
    param([Parameter(Mandatory)][string]$Command, [string[]]$Arguments = @())

    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Command failed with exit code $LASTEXITCODE." }
}

function Start-ContainerIfMissing {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Image,
        [Parameter(Mandatory)][string[]]$ContainerArguments,
        [string[]]$CommandArguments = @()
    )

    $existing = docker ps --all --filter "name=^/$Name$" --format '{{.Names}}'
    if ($existing -contains $Name) {
        $running = docker ps --filter "name=^/$Name$" --format '{{.Names}}'
        if ($running -contains $Name) {
            Write-Host "$Name is already running."
            return
        }

        Invoke-Checked docker @('start', $Name)
        return
    }

    Invoke-Checked docker (@('run', '--detach', '--name', $Name) + $ContainerArguments + @($Image) + $CommandArguments)
}

function Set-JsonValue {
    param(
        [Parameter(Mandatory)]$Object,
        [Parameter(Mandatory)][string]$Name,
        [AllowNull()][string]$Value
    )

    if ($Object.PSObject.Properties.Name -contains $Name) {
        $Object.$Name = $Value
        return
    }

    $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
}

Push-Location $repositoryRoot
try {
    Assert-Command dotnet
    Assert-Command npm
    Assert-Command func
    Assert-Command docker

    if (-not $SkipContracts) {
        Invoke-Checked npm @('ci')
        Invoke-Checked npm @('run', 'contracts:validate')
        Invoke-Checked npm @('run', 'gen:client')
    }

    Start-ContainerIfMissing `
        -Name 'docaya-azurite' `
        -Image 'mcr.microsoft.com/azure-storage/azurite:latest' `
        -ContainerArguments @(
            '--publish', '10000:10000',
            '--publish', '10001:10001',
            '--publish', '10002:10002',
            '--volume', "$repositoryRoot/.azurite:/data"
        ) `
        -CommandArguments @(
            'azurite', '--blobHost', '0.0.0.0', '--queueHost', '0.0.0.0', '--tableHost', '0.0.0.0', '--skipApiVersionCheck'
        )

    $sqlConnectionString = ''
    if (-not $SkipSql) {
        if ([string]::IsNullOrWhiteSpace($SqlPassword)) {
            throw 'Set DOCAYA_LOCAL_SQL_PASSWORD or pass -SqlPassword before starting local SQL. Use a local development password only.'
        }

        Start-ContainerIfMissing `
            -Name 'docaya-sql' `
            -Image 'mcr.microsoft.com/mssql/server:2022-latest' `
            -ContainerArguments @(
                '--env', 'ACCEPT_EULA=Y',
                '--env', "MSSQL_SA_PASSWORD=$SqlPassword",
                '--publish', '14333:1433'
            )
        $sqlConnectionString = "Server=localhost,14333;Database=DocayaDev;User Id=sa;Password=$SqlPassword;TrustServerCertificate=True;Encrypt=False"
    }

    if (-not (Test-Path -LiteralPath $functionsSettings -PathType Leaf)) {
        Copy-Item -LiteralPath $functionsSettingsTemplate -Destination $functionsSettings
    }

    $settings = Get-Content -LiteralPath $functionsSettings -Raw | ConvertFrom-Json
    Set-JsonValue -Object $settings.Values -Name 'AzureWebJobsStorage' -Value 'UseDevelopmentStorage=true'
    Set-JsonValue -Object $settings.Values -Name 'FUNCTIONS_WORKER_RUNTIME' -Value 'dotnet-isolated'
    Set-JsonValue -Object $settings.Values -Name 'ConnectionStrings:DocayaSql' -Value $sqlConnectionString
    Set-JsonValue -Object $settings.Values -Name 'Docaya:UseMockGraphAdapter' -Value 'true'
    Set-JsonValue -Object $settings.Values -Name 'Docaya:UseMockSearchAdapter' -Value 'true'

    if (-not $SkipServiceBus) {
        Write-Warning 'Service Bus emulator is not started by this script yet. Set Values.DocayaServiceBus in src/functions/local.settings.json before enabling Service Bus-trigger smoke tests.'
    }

    $settings | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $functionsSettings -Encoding utf8

    $apiEnv = @{
        'ASPNETCORE_ENVIRONMENT' = 'Development'
        'ASPNETCORE_URLS' = 'https://localhost:5001;http://localhost:5000'
        'ConnectionStrings__DocayaSql' = $sqlConnectionString
        'Docaya__UseMockGraphAdapter' = 'true'
        'Docaya__UseMockSearchAdapter' = 'true'
    }
    $apiEnvScript = ($apiEnv.GetEnumerator() | ForEach-Object { "Set-Item -Path 'Env:\$($_.Key)' -Value '$($_.Value -replace "'", "''")'" }) -join '; '
    Start-Process powershell -ArgumentList @('-NoExit', '-Command', "$apiEnvScript; dotnet run --project '$apiProject'") -WorkingDirectory $repositoryRoot

    if (-not $SkipFunctions) {
        Start-Process powershell -ArgumentList @('-NoExit', '-Command', 'func start') -WorkingDirectory $functionsRoot
    }

    if (-not $SkipWeb) {
        Start-Process powershell -ArgumentList @('-NoExit', '-Command', "`$env:DOCAYA_API_PROXY = 'https://localhost:5001'; npm run dev --workspace @docaya/web") -WorkingDirectory $repositoryRoot
    }

    Write-Host 'Local Docaya dev stack launch requested.'
    Write-Host 'API:       https://localhost:5001/health/live'
    Write-Host 'Web:       http://localhost:5173'
    Write-Host 'Azurite:   http://localhost:10000, 10001, 10002'
    if (-not $SkipSql) { Write-Host 'SQL:       localhost,14333 / DocayaDev' }
    Write-Host 'Azure runtime cost: $0 for this local path; cloud parity still requires a hosted smoke environment.'
}
finally {
    Pop-Location
}
