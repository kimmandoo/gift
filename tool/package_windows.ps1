param(
  [string]$ReleaseDirectory = '',
  [string]$OutputPath = '',
  [string]$SetupOutputPath = ''
)


$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ReleaseDirectory)) {
  $ReleaseDirectory = Join-Path $repositoryRoot 'build\windows\x64\runner\Release'
}
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $OutputPath = Join-Path $repositoryRoot 'build\windows\x64\runner\gift-portable.exe'
}
if ([string]::IsNullOrWhiteSpace($SetupOutputPath)) {
  $SetupOutputPath = Join-Path $repositoryRoot 'build\windows\x64\runner\gift-setup.zip'
}


$releaseDirectory = (Resolve-Path -LiteralPath $ReleaseDirectory).Path
$iexpress = Join-Path $env:WINDIR 'System32\iexpress.exe'
if (-not (Test-Path -LiteralPath $iexpress -PathType Leaf)) {
  throw 'IExpress was not found. Windows portable packaging requires iexpress.exe.'
}

$packageDirectory = Join-Path $env:TEMP ('gift-portable-package-' + [guid]::NewGuid().ToString('N'))
$payloadPath = Join-Path $packageDirectory 'payload.zip'
$sedPath = Join-Path $packageDirectory 'package.sed'
$launcherVbs = Join-Path $PSScriptRoot 'windows_portable_launcher.vbs'
$launcherScript = Join-Path $PSScriptRoot 'windows_portable_launcher.ps1'

try {
  New-Item -ItemType Directory -Path $packageDirectory -Force | Out-Null
  Compress-Archive -Path (Join-Path $releaseDirectory '*') -DestinationPath $payloadPath -CompressionLevel Optimal
  Copy-Item -LiteralPath $launcherVbs -Destination $packageDirectory
  Copy-Item -LiteralPath $launcherScript -Destination $packageDirectory

  $targetDirectory = Split-Path -Parent $OutputPath
  New-Item -ItemType Directory -Path $targetDirectory -Force | Out-Null
  if (Test-Path -LiteralPath $OutputPath) {
    Remove-Item -LiteralPath $OutputPath -Force
  }

  $sed = @"
[Version]
Class=IEXPRESS
SEDVersion=3

[Options]
PackagePurpose=InstallApp
ShowInstallProgramWindow=0
HideExtractAnimation=1
UseLongFileName=1
InsideCompressed=1
CAB_FixedSize=0
CAB_ResvCodeSigning=0
RebootMode=I
InstallPrompt=%InstallPrompt%
DisplayLicense=%DisplayLicense%
FinishMessage=%FinishMessage%
TargetName=%TargetName%
FriendlyName=%FriendlyName%
AppLaunched=%AppLaunched%
PostInstallCmd=<None>
AdminQuietInstCmd=
UserQuietInstCmd=
SourceFiles=SourceFiles

[Strings]
InstallPrompt=
DisplayLicense=
FinishMessage=
TargetName=$OutputPath
FriendlyName=GIFT Portable
AppLaunched=wscript.exe windows_portable_launcher.vbs
FILE0="payload.zip"
FILE1="windows_portable_launcher.vbs"
FILE2="windows_portable_launcher.ps1"

[SourceFiles]
SourceFiles0="$packageDirectory"

[SourceFiles0]
%FILE0%=
%FILE1%=
%FILE2%=
"@
  Set-Content -LiteralPath $sedPath -Value $sed -Encoding ASCII
  Start-Process -FilePath $iexpress -ArgumentList @('/N', '/Q', $sedPath) -Wait
  if (-not (Test-Path -LiteralPath $OutputPath -PathType Leaf)) {
    throw "IExpress failed to create the portable package: $OutputPath"
  }

  Write-Output "Portable Windows executable: $OutputPath"
} finally {
  if (Test-Path -LiteralPath $packageDirectory) {
    Remove-Item -LiteralPath $packageDirectory -Recurse -Force -ErrorAction SilentlyContinue
  }
}
& (Join-Path $PSScriptRoot 'package_windows_setup.ps1') `
  -ReleaseDirectory $releaseDirectory `
  -OutputPath $SetupOutputPath
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}
