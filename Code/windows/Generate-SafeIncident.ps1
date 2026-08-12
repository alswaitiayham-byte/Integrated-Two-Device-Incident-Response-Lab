#Requires -Version 5.1
#Requires -RunAsAdministrator
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$LabRoot = 'C:\IR-Lab'
$EvidenceDirectory = Join-Path $LabRoot 'evidence'
$SimulationLog = Join-Path $LabRoot 'safe-incident.jsonl'
$EventSource = 'IRCourseLab'
$EventId = 'IR-WIN-SIM-{0}' -f ([DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ'))
$SourceIp = '198.51.100.77'
$CallbackIp = '203.0.113.50'

New-Item -ItemType Directory -Path $EvidenceDirectory -Force | Out-Null

if (-not [System.Diagnostics.EventLog]::SourceExists($EventSource)) {
    New-EventLog -LogName Application -Source $EventSource
}

function Add-SafeEvent {
    param(
        [Parameter(Mandatory)][string]$EventType,
        [Parameter(Mandatory)][string]$Message,
        [int]$WindowsEventId = 1000
    )
    $Record = [ordered]@{
        datetime = [DateTime]::UtcNow.ToString('o')
        timestamp_desc = 'Safe simulation event time'
        event_id = $EventId
        event_type = $EventType
        hostname = $env:COMPUTERNAME
        user = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        message = $Message
        tag = 'SAFE-SIMULATION'
    }
    ($Record | ConvertTo-Json -Compress) | Add-Content -LiteralPath $SimulationLog -Encoding UTF8
    Write-EventLog -LogName Application -Source $EventSource -EventId $WindowsEventId `
        -EntryType Information -Message "[SAFE-SIMULATION][$EventId] $Message"
}

Add-SafeEvent -EventType 'preparation' -Message 'Authorized non-malicious Windows incident simulation started.' -WindowsEventId 1000
foreach ($Attempt in 1..6) {
    Add-SafeEvent -EventType 'authentication_failure' `
        -Message "Simulated failed authentication attempt $Attempt for demo_admin from documentation address $SourceIp; no real login occurred." `
        -WindowsEventId 1001
}
Add-SafeEvent -EventType 'authentication_success' `
    -Message "Simulated authentication success marker for demo_admin from documentation address $SourceIp; no account was accessed." `
    -WindowsEventId 1002

$ProtectedFile = Join-Path $EvidenceDirectory 'customer-demo.txt'
'Synthetic Windows customer record for the authorized IR course lab only.' | Set-Content -LiteralPath $ProtectedFile -Encoding UTF8
Add-Content -LiteralPath $ProtectedFile -Value "Updated at $([DateTime]::UtcNow.ToString('o'))"
Add-SafeEvent -EventType 'file_change' -Message "Created and modified harmless lab file $ProtectedFile" -WindowsEventId 1003

$MarkerFile = Join-Path $EvidenceDirectory 'suspicious-note.txt'
@(
    'SAFE-SIMULATION ONLY'
    "event_id=$EventId"
    "callback=$($CallbackIp):443"
    'The RFC 5737 documentation address was not contacted.'
) | Set-Content -LiteralPath $MarkerFile -Encoding UTF8
Add-SafeEvent -EventType 'ioc_observed' `
    -Message "Created an IOC marker for documentation address $($CallbackIp):443; network_contact=false." `
    -WindowsEventId 1004

$PidFile = Join-Path $LabRoot 'simulation-process.pid'
$ExistingPid = $null
if (Test-Path -LiteralPath $PidFile) {
    $ExistingPid = Get-Content -LiteralPath $PidFile -ErrorAction SilentlyContinue | Select-Object -First 1
}
if (-not ($ExistingPid -as [int]) -or -not (Get-Process -Id ([int]$ExistingPid) -ErrorAction SilentlyContinue)) {
    $Process = Start-Process -FilePath 'powershell.exe' -PassThru -WindowStyle Minimized `
        -ArgumentList '-NoProfile', '-Command', 'Start-Sleep -Seconds 900'
    $Process.Id | Set-Content -LiteralPath $PidFile -Encoding ASCII
    Add-SafeEvent -EventType 'process_start' `
        -Message "Started harmless labelled sleep process PID $($Process.Id) for volatile-evidence collection." `
        -WindowsEventId 1005
}

$Hashes = Get-ChildItem -LiteralPath $EvidenceDirectory -File | Get-FileHash -Algorithm SHA256
$Hashes | Select-Object Path, Hash, Algorithm | Export-Csv -LiteralPath (Join-Path $EvidenceDirectory 'initial-file-hashes.csv') -NoTypeInformation
Add-SafeEvent -EventType 'completion' -Message 'Safe Windows incident simulation completed.' -WindowsEventId 1006

Write-Host 'WINDOWS SAFE INCIDENT RESULT: PASS' -ForegroundColor Green
Write-Host "Event ID: $EventId"
Write-Host "Simulation log: $SimulationLog"
