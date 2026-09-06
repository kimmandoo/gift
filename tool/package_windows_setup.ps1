param(
  [string]$ReleaseDirectory = '',
  [string]$OutputPath = ''
)

$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ReleaseDirectory)) {
  $ReleaseDirectory = Join-Path $repositoryRoot 'build\windows\x64\runner\Release'
}
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $OutputPath = Join-Path $repositoryRoot 'build\windows\x64\runner\gift-setup.zip'
}

$releasePath = (Resolve-Path -LiteralPath $ReleaseDirectory).Path
$applicationPath = Join-Path $releasePath 'gift.exe'
if (-not (Test-Path -LiteralPath $applicationPath -PathType Leaf)) {
  throw "The Windows release directory does not contain gift.exe: $releasePath"
}

$targetDirectory = Split-Path -Parent $OutputPath
$temporaryDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ('gift-setup-package-' + [guid]::NewGuid().ToString('N'))
$runtimeArchive = Join-Path $temporaryDirectory 'gift-runtime.zip'
$setupStage = Join-Path $temporaryDirectory 'setup'

try {
  New-Item -ItemType Directory -Path $temporaryDirectory -Force | Out-Null
  New-Item -ItemType Directory -Path $setupStage -Force | Out-Null
  New-Item -ItemType Directory -Path $targetDirectory -Force | Out-Null

  Compress-Archive -Path (Join-Path $releasePath '*') `
    -DestinationPath $runtimeArchive -CompressionLevel Optimal -Force

  @(
    'Install-Gift.ps1',
    'Install-Gift.vbs',
    'Uninstall-Gift.ps1',
    'Uninstall-Gift.vbs'
  ) | ForEach-Object {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $_) `
      -Destination (Join-Path $setupStage $_) -Force
  }
  Copy-Item -LiteralPath $runtimeArchive `
    -Destination (Join-Path $setupStage 'gift-runtime.zip') -Force

  @'
GIFT Setup
==========

Double-click Install-Gift.vbs to open the GUI installation wizard.
The launcher starts Windows PowerShell without opening a console window.
The installed folder contains Uninstall-Gift.vbs for removing GIFT later.
The setup payload contains the complete Flutter Windows release bundle.
Git must still be installed separately because GIFT uses the system Git
executable.
'@ | Set-Content -LiteralPath (Join-Path $setupStage 'README.txt') -Encoding UTF8

  if (Test-Path -LiteralPath $OutputPath) {
    Remove-Item -LiteralPath $OutputPath -Force
  }
  Compress-Archive -Path (Join-Path $setupStage '*') `
    -DestinationPath $OutputPath -CompressionLevel Optimal -Force
  Write-Output "Windows setup bundle: $OutputPath"
} finally {
  if (Test-Path -LiteralPath $temporaryDirectory) {
    Remove-Item -LiteralPath $temporaryDirectory -Recurse -Force -ErrorAction SilentlyContinue
  }
}
