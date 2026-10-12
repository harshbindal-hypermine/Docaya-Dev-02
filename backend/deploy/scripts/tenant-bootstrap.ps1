<# Plan or assign Sites.Selected for the EXISTING promotion managed identity.
API/SPA registration, scopes, roles and federation remain explicit readiness blockers. #>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$ConfigurationFile, [switch]$Execute)
. "$PSScriptRoot/common.ps1"
$config = Read-JsonFile $ConfigurationFile
if (-not $Execute) {
    [ordered]@{
        mode = 'PLAN_ONLY'; tenantId = $config.tenantId
        identityObjectId = $config.promotionIdentityObjectId; identityClientId = $config.promotionIdentityClientId
        graphApplicationPermission = 'Sites.Selected'; sitePermission = 'write'; sites = @($config.sharePointSiteIds)
        prerequisite = 'Approved API/SPA registrations, scopes/roles, federation and existing promotion managed identity. Tenant administrator must have the required Graph permissions.'
    } | ConvertTo-Json -Depth 5
    return
}
foreach ($key in @('tenantId', 'subscriptionId', 'promotionIdentityObjectId', 'promotionIdentityClientId')) {
    $identifier = [guid]::Empty
    if (-not [guid]::TryParse([string]$config.$key, [ref]$identifier) -or $identifier -eq [guid]::Empty) { throw "Configure a valid $key." }
}
if (@($config.sharePointSiteIds).Count -eq 0) { throw 'Configure explicit SharePoint site IDs.' }
foreach ($site in $config.sharePointSiteIds) {
    if ($site -notmatch '^[A-Za-z0-9.-]+,[a-fA-F0-9-]{36},[a-fA-F0-9-]{36}$') { throw 'Expected a Graph composite SharePoint site ID.' }
}
Assert-AzureContext $config
function Invoke-Graph {
    param([string]$Method, [string]$Url, $Body = $null)
    if (-not $Url.StartsWith('https://graph.microsoft.com/v1.0/', [StringComparison]::Ordinal)) { throw 'Unexpected Graph URL.' }
    $arguments = @('rest', '--method', $Method, '--url', $Url, '--output', 'json', '--only-show-errors')
    $bodyFile = $null
    try {
        if ($null -ne $Body) {
            $bodyFile = [IO.Path]::GetTempFileName()
            [IO.File]::WriteAllText($bodyFile, ($Body | ConvertTo-Json -Depth 10), [Text.UTF8Encoding]::new($false))
            $arguments += @('--headers', 'Content-Type=application/json', '--body', "@$bodyFile")
        }
        $result = Invoke-Checked az $arguments
        if ($result) { return (($result -join "`n") | ConvertFrom-Json) }
    }
    finally { if ($bodyFile) { Remove-Item -LiteralPath $bodyFile -Force } }
}
function Get-GraphCollection {
    param([string]$Url)
    while ($Url) {
        $page = Invoke-Graph GET $Url
        $page.value
        $next = $page.PSObject.Properties['@odata.nextLink']
        $Url = if ($next) { [string]$next.Value } else { '' }
    }
}
$principalUrl = "https://graph.microsoft.com/v1.0/servicePrincipals/$($config.promotionIdentityObjectId)"
$principal = Invoke-Graph GET $principalUrl
if ($principal.appId -ne $config.promotionIdentityClientId -or $principal.servicePrincipalType -ne 'ManagedIdentity') { throw 'Object/client IDs do not match a managed identity.' }
$graph = @(Get-GraphCollection 'https://graph.microsoft.com/v1.0/servicePrincipals?$filter=appId%20eq%20%2700000003-0000-0000-c000-000000000000%27')
if ($graph.Count -ne 1) { throw 'Microsoft Graph service principal was not resolved uniquely.' }
$role = @($graph[0].appRoles | Where-Object { $_.value -eq 'Sites.Selected' -and $_.isEnabled -and 'Application' -in $_.allowedMemberTypes })
if ($role.Count -ne 1) { throw 'Sites.Selected application role was not resolved uniquely.' }
$assignments = @(Get-GraphCollection "$principalUrl/appRoleAssignments")
if (-not ($assignments | Where-Object { $_.resourceId -eq $graph[0].id -and $_.appRoleId -eq $role[0].id })) {
    $null = Invoke-Graph POST "$principalUrl/appRoleAssignments" @{ principalId = $principal.id; resourceId = $graph[0].id; appRoleId = $role[0].id }
}
foreach ($site in $config.sharePointSiteIds) {
    $url = "https://graph.microsoft.com/v1.0/sites/$site/permissions"
    $permissions = @(Get-GraphCollection $url)
    $existing = @($permissions | Where-Object {
        $identities = $_.PSObject.Properties['grantedToIdentitiesV2']
        if (-not $identities) { $identities = $_.PSObject.Properties['grantedToIdentities'] }
        if ($identities) { @($identities.Value | Where-Object { $_.PSObject.Properties['application'] -and $_.application.id -eq $config.promotionIdentityClientId }).Count -gt 0 }
    })
    if ($existing.Count -gt 0) {
        if ($existing.Count -ne 1 -or @($existing[0].roles).Count -ne 1 -or $existing[0].roles[0] -ne 'write') { throw 'Existing site permissions differ from the requested write-only grant. Review explicitly.' }
    } else {
        $null = Invoke-Graph POST $url @{ roles = @('write'); grantedToIdentities = @(@{ application = @{ id = $config.promotionIdentityClientId; displayName = $principal.displayName } }) }
    }
}
Write-Host 'Sites.Selected and explicit site write grants verified.'
