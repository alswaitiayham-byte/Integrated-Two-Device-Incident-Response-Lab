#Requires -Version 5.1
#Requires -RunAsAdministrator
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$GroupName = 'Ayham IR Safe Containment'
$Addresses = @('198.51.100.77', '203.0.113.50')

$Existing = Get-NetFirewallRule -Group $GroupName -ErrorAction SilentlyContinue
if ($Existing) {
    Write-Host 'Safe containment rules already exist; no duplicate rules were created.' -ForegroundColor Yellow
}
else {
    New-NetFirewallRule -DisplayName 'Ayham IR - Block simulated IOCs outbound' -Group $GroupName `
        -Direction Outbound -Action Block -Enabled True -Profile Any -RemoteAddress $Addresses `
        -Description 'Course-lab containment: blocks RFC 5737 documentation-only IOCs; does not isolate the computer.' | Out-Null
    New-NetFirewallRule -DisplayName 'Ayham IR - Block simulated IOCs inbound' -Group $GroupName `
        -Direction Inbound -Action Block -Enabled True -Profile Any -RemoteAddress $Addresses `
        -Description 'Course-lab containment: blocks RFC 5737 documentation-only IOCs; does not isolate the computer.' | Out-Null
}

$StatusPath = 'C:\IR-Evidence\windows-containment-status.txt'
New-Item -ItemType Directory -Path (Split-Path -Parent $StatusPath) -Force | Out-Null
Get-NetFirewallRule -Group $GroupName | Get-NetFirewallAddressFilter | Format-List * | Out-File -LiteralPath $StatusPath -Encoding UTF8

Write-Host 'WINDOWS TARGETED CONTAINMENT RESULT: PASS' -ForegroundColor Green
Write-Host 'Only two RFC 5737 simulation addresses were blocked; normal LAN/Internet access remains available.'
Write-Host 'Rollback command: .\Rollback-Containment.ps1'
