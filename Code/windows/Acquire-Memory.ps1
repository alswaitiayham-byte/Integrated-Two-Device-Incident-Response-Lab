#Requires -Version 5.1
#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ToolPath,
    [string]$OutputDirectory = 'C:\IR-Evidence\Memory',
    [ValidateSet('Auto', 'GoWinPmem', 'LegacyWinPmem')]
    [string]$ToolMode = 'Auto'
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $ToolPath -PathType Leaf)) {
    throw 'WinPmem tool not found. Download a signed release from the official Velocidex/WinPmem repository.'
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$ResolvedOutput = (Resolve-Path -LiteralPath $OutputDirectory).Path
$DriveName = (Split-Path -Qualifier $ResolvedOutput).TrimEnd(':')
$Drive = Get-PSDrive -Name $DriveName
$MemoryBytes = [int64](Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory
$RequiredBytes = $MemoryBytes + 1GB
if ($Drive.Free -lt $RequiredBytes) {
    throw "Not enough free space. Required at least $([Math]::Ceiling($RequiredBytes / 1GB)) GiB, available $([Math]::Floor($Drive.Free / 1GB)) GiB."
}

$RunId = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ')
$ImagePath = Join-Path $ResolvedOutput "windows-memory-$env:COMPUTERNAME-$RunId.raw"
$MetadataPath = "$ImagePath.metadata.txt"
$ToolHash = (Get-FileHash -LiteralPath $ToolPath -Algorithm SHA256).Hash.ToLowerInvariant()
$ToolLeafName = [IO.Path]::GetFileName($ToolPath)

if ($ToolMode -eq 'Auto') {
    if ($ToolLeafName -like 'go-winpmem*') {
        $EffectiveToolMode = 'GoWinPmem'
    }
    else {
        $EffectiveToolMode = 'LegacyWinPmem'
    }
}
else {
    $EffectiveToolMode = $ToolMode
}

if ($EffectiveToolMode -eq 'GoWinPmem') {
    # The signed Go WinPmem release uses a subcommand-based CLI.
    $ToolArguments = @('acquire', '--progress', $ImagePath)
}
else {
    # Legacy winpmem_mini executables accept the image as a positional argument.
    $ToolArguments = @($ImagePath)
}

@(
    'AUTHORIZED MEMORY ACQUISITION'
    'Case ID: IR-COURSE-12116003'
    "Source computer: $env:COMPUTERNAME"
    "Operator: $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)"
    "UTC start: $([DateTime]::UtcNow.ToString('o'))"
    "Tool path: $ToolPath"
    "Tool SHA-256: $ToolHash"
    "Tool invocation mode: $EffectiveToolMode"
    "Tool arguments: $($ToolArguments -join ' ')"
    "Output image: $ImagePath"
) | Set-Content -LiteralPath $MetadataPath -Encoding UTF8

Write-Host 'Memory acquisition may take several minutes. Do not close this window.' -ForegroundColor Yellow
$Process = Start-Process -FilePath $ToolPath -ArgumentList $ToolArguments -Wait -PassThru -NoNewWindow
if ($Process.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $ImagePath -PathType Leaf)) {
    throw "Memory acquisition failed with exit code $($Process.ExitCode). Preserve the console/metadata for troubleshooting."
}

$ImageHash = (Get-FileHash -LiteralPath $ImagePath -Algorithm SHA256).Hash.ToLowerInvariant()
@(
    "UTC completion: $([DateTime]::UtcNow.ToString('o'))"
    "Image size: $((Get-Item -LiteralPath $ImagePath).Length) bytes"
    "Image SHA-256: $ImageHash"
) | Add-Content -LiteralPath $MetadataPath -Encoding UTF8
"$ImageHash  $([IO.Path]::GetFileName($ImagePath))" | Set-Content -LiteralPath "$ImagePath.sha256" -Encoding ASCII

Write-Host 'WINDOWS MEMORY ACQUISITION RESULT: PASS' -ForegroundColor Green
Write-Host "Memory image: $ImagePath"
Write-Host "SHA-256: $ImageHash"
