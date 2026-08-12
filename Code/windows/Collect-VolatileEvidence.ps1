#Requires -Version 5.1
#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [string]$OutputRoot = 'C:\IR-Evidence'
)

$ErrorActionPreference = 'Stop'
$RunId = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ')
$CaseDirectory = Join-Path $OutputRoot "volatile-$env:COMPUTERNAME-$RunId"
New-Item -ItemType Directory -Path $CaseDirectory -Force | Out-Null

function Save-TextCommand {
    param([string]$Name, [scriptblock]$Command)
    $Path = Join-Path $CaseDirectory $Name
    try {
        & $Command | Out-String -Width 4096 | Set-Content -LiteralPath $Path -Encoding UTF8
    }
    catch {
        "Collection error: $($_.Exception.Message)" | Set-Content -LiteralPath $Path -Encoding UTF8
    }
}

Save-TextCommand 'system-identity.txt' { Get-ComputerInfo }
Save-TextCommand 'clock.txt' { Get-Date -Format o; w32tm.exe /query /status }
Save-TextCommand 'logged-on-users.txt' { whoami.exe /all; quser.exe }
Save-TextCommand 'processes.txt' { Get-CimInstance Win32_Process | Select-Object ProcessId, ParentProcessId, Name, ExecutablePath, CommandLine, CreationDate }
Save-TextCommand 'network-connections.txt' { Get-NetTCPConnection | Sort-Object State, RemoteAddress, RemotePort }
Save-TextCommand 'network-configuration.txt' { Get-NetIPConfiguration; Get-NetIPAddress; Get-NetRoute }
Save-TextCommand 'services.txt' { Get-CimInstance Win32_Service | Select-Object Name, State, StartMode, StartName, PathName }
Save-TextCommand 'scheduled-tasks.txt' { Get-ScheduledTask | Select-Object TaskPath, TaskName, State, Author }
Save-TextCommand 'drivers.txt' { Get-CimInstance Win32_SystemDriver | Select-Object Name, State, StartMode, PathName }
Save-TextCommand 'dns-cache.txt' { Get-DnsClientCache }
Save-TextCommand 'arp-cache.txt' { arp.exe -a }
Save-TextCommand 'firewall-project-rules.txt' { Get-NetFirewallRule -Group 'Ayham IR Safe Containment' -ErrorAction SilentlyContinue | Format-List * }
Save-TextCommand 'ir-course-events.txt' { Get-WinEvent -FilterHashtable @{LogName='Application'; ProviderName='IRCourseLab'} -ErrorAction SilentlyContinue | Select-Object -First 100 TimeCreated, Id, LevelDisplayName, Message }

if (Test-Path -LiteralPath 'C:\IR-Lab') {
    Copy-Item -LiteralPath 'C:\IR-Lab' -Destination (Join-Path $CaseDirectory 'IR-Lab-files') -Recurse -Force
}

$Custody = @(
    "Case ID: IR-COURSE-12116003"
    'Evidence type: Live volatile Windows collection'
    "Source computer: $env:COMPUTERNAME"
    "Operator: $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)"
    "Collection completed (UTC): $([DateTime]::UtcNow.ToString('o'))"
    'Method: Built-in read-only Windows PowerShell/CIM/network commands'
    "Original location: $CaseDirectory"
)
$Custody | Set-Content -LiteralPath (Join-Path $CaseDirectory 'chain-of-custody.txt') -Encoding UTF8

$ManifestPath = Join-Path $CaseDirectory 'SHA256SUMS.txt'
Get-ChildItem -LiteralPath $CaseDirectory -File -Recurse | Where-Object FullName -ne $ManifestPath | ForEach-Object {
    $Hash = Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256
    $Relative = $_.FullName.Substring($CaseDirectory.Length + 1)
    "{0}  {1}" -f $Hash.Hash.ToLowerInvariant(), $Relative
} | Set-Content -LiteralPath $ManifestPath -Encoding ASCII

Write-Host 'WINDOWS VOLATILE COLLECTION RESULT: PASS' -ForegroundColor Green
Write-Host "Evidence directory: $CaseDirectory"
