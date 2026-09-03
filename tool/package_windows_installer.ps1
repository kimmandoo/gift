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
  $OutputPath = Join-Path $repositoryRoot 'build\windows\x64\runner\gift-setup.exe'
}

$releaseDirectory = (Resolve-Path -LiteralPath $ReleaseDirectory).Path
$iexpress = Join-Path $env:WINDIR 'System32\iexpress.exe'
if (-not (Test-Path -LiteralPath $iexpress -PathType Leaf)) {
  throw 'IExpress was not found. Windows setup packaging requires iexpress.exe.'
}

$packageDirectory = Join-Path $env:TEMP ('gift-setup-package-' + [guid]::NewGuid().ToString('N'))
$payloadPath = Join-Path $packageDirectory 'payload.zip'
$sedPath = Join-Path $packageDirectory 'setup.sed'
$launcherVbs = Join-Path $PSScriptRoot 'windows_setup_launcher.vbs'
$launcherScript = Join-Path $PSScriptRoot 'windows_setup_launcher.ps1'
$uninstallerVbs = Join-Path $PSScriptRoot 'windows_uninstall.vbs'
$uninstallerScript = Join-Path $PSScriptRoot 'windows_uninstall.ps1'

try {
  New-Item -ItemType Directory -Path $packageDirectory -Force | Out-Null
  Compress-Archive -Path (Join-Path $releaseDirectory '*') -DestinationPath $payloadPath -CompressionLevel Optimal
  Copy-Item -LiteralPath $launcherVbs -Destination $packageDirectory
  Copy-Item -LiteralPath $launcherScript -Destination $packageDirectory
  Copy-Item -LiteralPath $uninstallerVbs -Destination $packageDirectory
  Copy-Item -LiteralPath $uninstallerScript -Destination $packageDirectory

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
FriendlyName=GIFT Setup
AppLaunched=wscript.exe windows_setup_launcher.vbs
FILE0="payload.zip"
FILE1="windows_setup_launcher.vbs"
FILE2="windows_setup_launcher.ps1"
FILE3="windows_uninstall.vbs"
FILE4="windows_uninstall.ps1"

[SourceFiles]
SourceFiles0="$packageDirectory"

[SourceFiles0]
%FILE0%=
%FILE1%=
%FILE2%=
%FILE3%=
%FILE4%=
"@
  Set-Content -LiteralPath $sedPath -Value $sed -Encoding ASCII
  Start-Process -FilePath $iexpress -ArgumentList @('/N', '/Q', $sedPath) -Wait
  if (-not (Test-Path -LiteralPath $OutputPath -PathType Leaf)) {
    throw "IExpress failed to create the Windows setup package: $OutputPath"
  }

  Write-Output "Windows setup executable: $OutputPath"
} finally {
  if (Test-Path -LiteralPath $packageDirectory) {
    Remove-Item -LiteralPath $packageDirectory -Recurse -Force -ErrorAction SilentlyContinue
  }
}
