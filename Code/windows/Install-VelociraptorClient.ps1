#Requires -Version 5.1
#Requires -RunAsAdministrator
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$BundleRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$InfoPath = Join-Path $BundleRoot 'server-info.env'
$ConfigSource = Join-Path $BundleRoot 'client.config.yaml'
$ExpectedExeHash = 'c91cf8a32731c4c45c148393bc7d2af688c392194a9fffc4535e8b583260d55e'

if (-not (Test-Path -LiteralPath $InfoPath -PathType Leaf)) {
    throw 'server-info.env is missing. Copy the complete generated Windows bundle.'
}
if (-not (Test-Path -LiteralPath $ConfigSource -PathType Leaf)) {
    throw 'client.config.yaml is missing. Copy the complete generated Windows bundle.'
}

$Info = @{}
foreach ($Line in Get-Content -LiteralPath $InfoPath) {
    if ($Line -match '^(?<Key>[A-Z0-9_]+)=(?<Value>.*)$') {
        $Info[$Matches.Key] = $Matches.Value
    }
}
$RequiredKeys = @('VELOCIRAPTOR_SERVER_IP', 'VELOCIRAPTOR_FRONTEND_PORT', 'VELOCIRAPTOR_VERSION')
foreach ($Key in $RequiredKeys) {
    if (-not $Info.ContainsKey($Key)) { throw "Missing $Key in server-info.env" }
}

$ExeName = "velociraptor-v$($Info.VELOCIRAPTOR_VERSION)-windows-amd64.exe"
$ExeSource = Join-Path $BundleRoot $ExeName
if (-not (Test-Path -LiteralPath $ExeSource -PathType Leaf)) {
    throw "Velociraptor executable is missing: $ExeName"
}

$ActualHash = (Get-FileHash -LiteralPath $ExeSource -Algorithm SHA256).Hash.ToLowerInvariant()
if ($ActualHash -ne $ExpectedExeHash) {
    throw "Velociraptor SHA-256 mismatch. Expected $ExpectedExeHash but found $ActualHash"
}

$Connection = Test-NetConnection -ComputerName $Info.VELOCIRAPTOR_SERVER_IP `
    -Port ([int]$Info.VELOCIRAPTOR_FRONTEND_PORT) -WarningAction SilentlyContinue
if (-not $Connection.TcpTestSucceeded) {
    throw "Cannot reach Ubuntu Velociraptor frontend at $($Info.VELOCIRAPTOR_SERVER_IP):$($Info.VELOCIRAPTOR_FRONTEND_PORT). Confirm both devices are on the same LAN."
}

$InstallRoot = Join-Path $env:ProgramFiles 'Velociraptor'
$EvidenceRoot = 'C:\IR-Evidence'
$ExeDestination = Join-Path $InstallRoot 'Velociraptor.exe'
$ConfigDestination = Join-Path $InstallRoot 'client.config.yaml'

$ExistingService = Get-Service -Name 'Velociraptor' -ErrorAction SilentlyContinue
if ($null -ne $ExistingService) {
    if (-not (Test-Path -LiteralPath $ExeDestination -PathType Leaf) -or
        -not (Test-Path -LiteralPath $ConfigDestination -PathType Leaf)) {
        throw 'An unmanaged Velociraptor service already exists. It was not changed or removed.'
    }
    $InstalledHash = (Get-FileHash -LiteralPath $ExeDestination -Algorithm SHA256).Hash.ToLowerInvariant()
    $ExpectedUrl = "https://$($Info.VELOCIRAPTOR_SERVER_IP):$($Info.VELOCIRAPTOR_FRONTEND_PORT)/"
    if ($InstalledHash -ne $ExpectedExeHash -or
        -not (Select-String -LiteralPath $ConfigDestination -SimpleMatch $ExpectedUrl -Quiet)) {
        throw 'The existing Velociraptor service does not match this project bundle. It was left unchanged.'
    }
    Start-Service -Name 'Velociraptor' -ErrorAction SilentlyContinue
    Write-Host "VELOCIRAPTOR WINDOWS CLIENT RESULT: PASS (existing project installation verified; status: $((Get-Service -Name 'Velociraptor').Status))" -ForegroundColor Green
    exit 0
}

New-Item -ItemType Directory -Path $InstallRoot -Force | Out-Null
New-Item -ItemType Directory -Path $EvidenceRoot -Force | Out-Null

Copy-Item -LiteralPath $ExeSource -Destination $ExeDestination -Force
Copy-Item -LiteralPath $ConfigSource -Destination $ConfigDestination -Force

& icacls.exe $ConfigDestination /inheritance:r /grant:r '*S-1-5-18:(F)' '*S-1-5-32-544:(F)' | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Failed to restrict the client configuration ACL.' }

& $ExeDestination --config $ConfigDestination service install
if ($LASTEXITCODE -ne 0) { throw "Velociraptor service installation failed with exit code $LASTEXITCODE" }

Start-Service -Name 'Velociraptor' -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
$Service = Get-Service -Name 'Velociraptor' -ErrorAction Stop
$Record = Join-Path $EvidenceRoot ("velociraptor-client-install-{0}.txt" -f (Get-Date -Format 'yyyyMMddTHHmmss'))
@(
    "UTC time: $([DateTime]::UtcNow.ToString('o'))"
    "Computer: $env:COMPUTERNAME"
    "Server: $($Info.VELOCIRAPTOR_SERVER_IP):$($Info.VELOCIRAPTOR_FRONTEND_PORT)"
    "Velociraptor version: $($Info.VELOCIRAPTOR_VERSION)"
    "Official executable SHA-256: $ActualHash"
    "Installed executable SHA-256: $((Get-FileHash -LiteralPath $ExeDestination -Algorithm SHA256).Hash.ToLowerInvariant())"
    "Service status: $($Service.Status)"
) | Set-Content -LiteralPath $Record -Encoding UTF8

Write-Host 'VELOCIRAPTOR WINDOWS CLIENT RESULT: PASS' -ForegroundColor Green
Write-Host "Evidence record: $Record"
