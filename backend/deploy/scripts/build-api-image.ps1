<# Builds and saves a local Docker image. Does not push to a registry or deploy. #>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$OutputArchive)
. "$PSScriptRoot/common.ps1"
$archive = [IO.Path]::GetFullPath($OutputArchive)
if (Test-Path -LiteralPath $archive) { throw 'Output archive already exists.' }
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { throw 'Docker is required for a local API image build.' }
$version = (Read-JsonFile (Join-Path $script:RepositoryRoot 'package.json')).version
$tag = "docaya-api:$version"
Invoke-Checked docker @('build', '--file', (Join-Path $script:RepositoryRoot 'src/api/Dockerfile'), '--tag', $tag, $script:RepositoryRoot)
$parentDirectory = Split-Path -Parent $archive
New-Item -ItemType Directory -Path $parentDirectory -Force | Out-Null
Invoke-Checked docker @('save', '--output', $archive, $tag)
Write-Host "Saved local image $tag to $archive. Registry publication and registry manifest digest verification have not been performed."
