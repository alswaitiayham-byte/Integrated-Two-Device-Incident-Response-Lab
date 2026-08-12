#Requires -Version 5.1
#Requires -RunAsAdministrator
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host '1/5 Generating the safe Windows incident...' -ForegroundColor Cyan
& (Join-Path $Root 'Generate-SafeIncident.ps1')
Write-Host '2/5 Collecting pre-containment volatile evidence...' -ForegroundColor Cyan
& (Join-Path $Root 'Collect-VolatileEvidence.ps1')
Write-Host '3/5 Applying narrow RFC 5737 IOC containment...' -ForegroundColor Cyan
& (Join-Path $Root 'Contain-SafeIncident.ps1')
Write-Host '4/5 Collecting containment-state evidence...' -ForegroundColor Cyan
& (Join-Path $Root 'Collect-VolatileEvidence.ps1')
Write-Host '5/5 Rolling back project containment and stopping the harmless process...' -ForegroundColor Cyan
& (Join-Path $Root 'Rollback-Containment.ps1')

Write-Host 'WINDOWS END-TO-END SAFE DEMO: PASS' -ForegroundColor Green
Write-Host 'Copy C:\IR-Evidence to the Ubuntu evidence partition after hashing/verification.'
Write-Host 'Memory acquisition is intentionally separate and optional: .\Acquire-Memory.ps1 -ToolPath C:\IR-Tools\go-winpmem_amd64_1.0-rc2_signed.exe'
