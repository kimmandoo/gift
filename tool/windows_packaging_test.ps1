$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot

function Read-RepositoryFile([string]$RelativePath) {
  $path = Join-Path $repositoryRoot $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    throw "Required packaging file was not found: $RelativePath"
  }
  return Get-Content -LiteralPath $path -Raw
}

function Assert-Contains([string]$Text, [string]$Needle, [string]$Description) {
  if ($Text.IndexOf($Needle, [System.StringComparison]::Ordinal) -lt 0) {
    throw "Packaging assertion failed: $Description"
  }
}

function Assert-NotContains([string]$Text, [string]$Needle, [string]$Description) {
  if ($Text.IndexOf($Needle, [System.StringComparison]::Ordinal) -ge 0) {
    throw "Packaging assertion failed: $Description"
  }
}

function Assert-PowerShellParses([string]$RelativePath) {
  $path = Join-Path $repositoryRoot $RelativePath
  $tokens = $null
  $errors = $null
  [System.Management.Automation.Language.Parser]::ParseFile(
    $path,
    [ref]$tokens,
    [ref]$errors
  ) | Out-Null
  if ($errors.Count -gt 0) {
    $messages = $errors | ForEach-Object { $_.Message }
    throw "PowerShell parse failed for ${RelativePath}: $($messages -join '; ')"
  }
}

$setupLauncher = Read-RepositoryFile 'tool/Install-Gift.ps1'
$portableLauncher = Read-RepositoryFile 'tool/windows_portable_launcher.ps1'
$setupBridge = Read-RepositoryFile 'tool/Install-Gift.vbs'
$portablePackage = Read-RepositoryFile 'tool/package_windows.ps1'
$setupPackage = Read-RepositoryFile 'tool/package_windows_setup.ps1'
$uninstaller = Read-RepositoryFile 'tool/Uninstall-Gift.ps1'
$uninstallBridge = Read-RepositoryFile 'tool/Uninstall-Gift.vbs'

@(
  'tool/Install-Gift.ps1',
  'tool/windows_portable_launcher.ps1',
  'tool/package_windows.ps1',
  'tool/package_windows_setup.ps1',
  'tool/Uninstall-Gift.ps1'
) | ForEach-Object { Assert-PowerShellParses $_ }

Assert-Contains $setupLauncher 'System.Windows.Forms.Form' 'setup uses a visible WinForms wizard'
Assert-Contains $setupLauncher 'ShowDialog()' 'setup blocks on the wizard until the user finishes or cancels'
Assert-Contains $setupLauncher 'Choose install options' 'setup exposes an installation-options page'
Assert-Contains $setupLauncher 'CreateStartMenu' 'setup keeps shortcut selection in wizard state'
Assert-Contains $setupLauncher 'Browse...' 'setup lets the user choose an install directory'
Assert-Contains $setupBridge 'shell.Run command, 0, False' 'VBScript launches the wizard without a console window'
Assert-Contains $setupBridge 'Install-Gift.ps1' 'VBScript launches the installer script'
Assert-Contains $setupBridge 'gift-runtime.zip' 'VBScript launches the bundled runtime payload'

Assert-Contains $portableLauncher 'Start-Process -FilePath $applicationPath -WorkingDirectory $extractDirectory -Wait' 'portable waits for the extracted app and cleans up afterward'
Assert-NotContains $portableLauncher 'System.Windows.Forms.Form' 'portable does not contain an installer wizard'
Assert-Contains $portablePackage 'FriendlyName=GIFT Portable' 'portable package keeps its portable identity'
Assert-Contains $setupPackage 'gift-runtime.zip' 'setup bundle contains the runtime archive'
Assert-Contains $setupPackage 'Install-Gift.vbs' 'setup bundle contains the VBScript installer entry point'
Assert-Contains $setupPackage 'Uninstall-Gift.vbs' 'setup bundle contains the VBScript uninstall entry point'
Assert-NotContains $setupPackage 'IExpress' 'setup bundle does not depend on IExpress'
Assert-Contains $setupLauncher 'Uninstall GIFT.lnk' 'setup creates a Start Menu uninstall shortcut'
Assert-Contains $setupLauncher 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\gift' 'setup registers the current-user uninstaller'
Assert-Contains $uninstaller 'Remove-ShortcutIfTarget' 'uninstall only removes matching shortcuts'
Assert-Contains $uninstaller 'SkipConfirmation' 'uninstall supports a confirmation-free cleanup handoff'
Assert-Contains $uninstallBridge 'shell.Run command, 0, False' 'uninstall VBScript launches PowerShell without a console window'
Assert-Contains $uninstallBridge 'Uninstall-Gift.ps1' 'uninstall bridge invokes the bundled PowerShell script'

Write-Output 'Windows packaging verification passed: setup bundle and portable launcher are distinct.'
