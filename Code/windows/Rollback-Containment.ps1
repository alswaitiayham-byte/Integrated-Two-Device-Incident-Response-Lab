#Requires -Version 5.1
#Requires -RunAsAdministrator
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$GroupName = 'Ayham IR Safe Containment'
$Rules = Get-NetFirewallRule -Group $GroupName -ErrorAction SilentlyContinue
if ($Rules) {
    $Rules | Remove-NetFirewallRule
    Write-Host 'Removed only the project safe-containment firewall rules.' -ForegroundColor Green
}
else {
    Write-Host 'No project containment rules were present.'
}

$PidFile = 'C:\IR-Lab\simulation-process.pid'
if (Test-Path -LiteralPath $PidFile) {
    $SimulationPid = Get-Content -LiteralPath $PidFile -ErrorAction SilentlyContinue | Select-Object -First 1
    if (($SimulationPid -as [int]) -and (Get-Process -Id ([int]$SimulationPid) -ErrorAction SilentlyContinue)) {
        Stop-Process -Id ([int]$SimulationPid) -Force
        Write-Host "Stopped harmless simulation process PID $SimulationPid."
    }
    Remove-Item -LiteralPath $PidFile -Force -ErrorAction SilentlyContinue
}

"UTC rollback time: $([DateTime]::UtcNow.ToString('o'))" | Set-Content -LiteralPath 'C:\IR-Evidence\windows-containment-rollback.txt' -Encoding UTF8
Write-Host 'WINDOWS CONTAINMENT ROLLBACK RESULT: PASS' -ForegroundColor Green
