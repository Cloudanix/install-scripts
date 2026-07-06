#Requires -Version 5.1
<#
.SYNOPSIS
  Installs the Cloudanix coding-agent guard CLI (cdxai) on Windows.

.DESCRIPTION
  The Windows counterpart of the bash installer served at install.cloudanix.com/cdxai.
  Downloads the prebuilt cdxai.exe for this machine's architecture from the
  public Cloudanix/artifacts repo, verifies it against a SHA256 sidecar, installs
  it to %USERPROFILE%\.cdxai\bin, and adds that to your USER PATH. No admin
  rights, nothing installed globally.

  One-liner:
    irm https://install.cloudanix.com/cdxai.ps1 | iex

  Pin a version:
    $env:CDXAI_VERSION = "1.0.0"; irm https://install.cloudanix.com/cdxai.ps1 | iex

.NOTES
  Served at install.cloudanix.com/cdxai.ps1 (GitHub Pages), mirroring how the
  bash `cdxai` installer is served. Kept in sync with the guard repo's
  scripts/cdxai.ps1 (the source of truth). MIT. Audit before running.

  Newly published for Windows — if you hit a PowerShell-specific issue (arch
  detection, Expand-Archive, PATH persistence), please report it.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Base       = 'https://github.com/Cloudanix/artifacts/raw/main/coding-agent-guard'
$InstallDir = Join-Path $HOME '.cdxai\bin'

function Fail($msg) { Write-Error "cdxai install: $msg"; exit 1 }

# 1. Resolve the version — an explicit CDXAI_VERSION, else the published pointer.
$Version = $env:CDXAI_VERSION
if ([string]::IsNullOrWhiteSpace($Version)) {
  try {
    $Version = (Invoke-WebRequest -Uri "$Base/LATEST_VERSION" -UseBasicParsing).Content.Trim()
  } catch {
    Fail "could not fetch LATEST_VERSION from $Base (check your connection)"
  }
}
if ([string]::IsNullOrWhiteSpace($Version)) { Fail "empty version" }

# 2. Map the CPU arch to the archive suffix (matches goreleaser name_template:
#    amd64 -> x86_64, arm64 -> arm64). PROCESSOR_ARCHITEW6432 covers 32-bit
#    PowerShell running on 64-bit Windows (WOW64).
$RawArch = $env:PROCESSOR_ARCHITEW6432
if ([string]::IsNullOrEmpty($RawArch)) { $RawArch = $env:PROCESSOR_ARCHITECTURE }
switch ($RawArch) {
  'AMD64' { $Arch = 'x86_64' }
  'ARM64' { $Arch = 'arm64' }
  default { Fail "unsupported architecture '$RawArch' (need AMD64 or ARM64)" }
}

$Archive = "cdxai_${Version}_windows_${Arch}.zip"
$Url     = "$Base/$Archive"
Write-Host "==> installing cdxai $Version ($Arch)"

# 3. Download the archive + its SHA256 sidecar into a temp dir.
$Tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("cdxai-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $Tmp -Force | Out-Null
try {
  $ZipPath = Join-Path $Tmp $Archive
  $ShaPath = "$ZipPath.sha256"
  Invoke-WebRequest -Uri $Url          -OutFile $ZipPath -UseBasicParsing
  Invoke-WebRequest -Uri "$Url.sha256" -OutFile $ShaPath -UseBasicParsing

  # 4. Verify the checksum (sidecar is coreutils '<hex>  <name>').
  $Want = ((Get-Content -Raw $ShaPath) -split '\s+')[0].ToLower()
  $Got  = (Get-FileHash -Algorithm SHA256 -Path $ZipPath).Hash.ToLower()
  if ($Want -ne $Got) { Fail "checksum mismatch (expected $Want, got $Got) - aborting" }
  Write-Host "    checksum OK"

  # 5. Extract cdxai.exe and install it.
  Expand-Archive -Path $ZipPath -DestinationPath $Tmp -Force
  $Exe = Get-ChildItem -Path $Tmp -Recurse -Filter 'cdxai.exe' | Select-Object -First 1
  if (-not $Exe) { Fail "cdxai.exe not found in the archive" }
  New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
  Copy-Item -Path $Exe.FullName -Destination (Join-Path $InstallDir 'cdxai.exe') -Force
  Write-Host "    installed to $InstallDir\cdxai.exe"
} finally {
  Remove-Item -Path $Tmp -Recurse -Force -ErrorAction SilentlyContinue
}

# 6. Ensure the install dir is on the USER PATH (persisted + current session).
$UserPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if (($UserPath -split ';') -notcontains $InstallDir) {
  $NewPath = if ([string]::IsNullOrEmpty($UserPath)) { $InstallDir } else { "$UserPath;$InstallDir" }
  [Environment]::SetEnvironmentVariable('Path', $NewPath, 'User')
  Write-Host "    added $InstallDir to your user PATH (new terminals pick it up)"
}
if (($env:Path -split ';') -notcontains $InstallDir) { $env:Path = "$env:Path;$InstallDir" }

Write-Host ""
Write-Host "cdxai $Version installed. Next:"
Write-Host "  cdxai configure --console-url <url> --email <you> --api-token <token>"
Write-Host "  cdxai install"
Write-Host "  cdxai sync --force"
