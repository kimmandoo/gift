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

$setupLauncher = Read-RepositoryFile 'tool/windows_setup_launcher.ps1'
$portableLauncher = Read-RepositoryFile 'tool/windows_portable_launcher.ps1'
$setupBridge = Read-RepositoryFile 'tool/windows_setup_launcher.vbs'
$portablePackage = Read-RepositoryFile 'tool/package_windows.ps1'
$setupPackage = Read-RepositoryFile 'tool/package_windows_installer.ps1'

@(
  'tool/windows_setup_launcher.ps1',
  'tool/windows_portable_launcher.ps1',
  'tool/package_windows.ps1',
  'tool/package_windows_installer.ps1',
  'tool/windows_uninstall.ps1'
) | ForEach-Object { Assert-PowerShellParses $_ }

Assert-Contains $setupLauncher 'System.Windows.Forms.Form' 'setup uses a visible WinForms wizard'
Assert-Contains $setupLauncher 'ShowDialog()' 'setup blocks on the wizard until the user finishes or cancels'
Assert-Contains $setupLauncher 'Choose install options' 'setup exposes an installation-options page'
Assert-Contains $setupLauncher 'CreateStartMenu' 'setup keeps shortcut selection in wizard state'
Assert-Contains $setupLauncher 'Browse...' 'setup lets the user choose an install directory'
Assert-Contains $setupBridge '-STA' 'setup starts PowerShell in STA mode for WinForms'

Assert-Contains $portableLauncher 'Start-Process -FilePath $applicationPath -WorkingDirectory $extractDirectory -Wait' 'portable waits for the extracted app and cleans up afterward'
Assert-NotContains $portableLauncher 'System.Windows.Forms.Form' 'portable does not contain an installer wizard'
Assert-Contains $portablePackage 'FriendlyName=GIFT Portable' 'portable package keeps its portable identity'
Assert-Contains $setupPackage 'FriendlyName=GIFT Setup' 'setup package keeps its installer identity'
Assert-Contains $setupPackage 'AppLaunched=wscript.exe windows_setup_launcher.vbs' 'setup defaults to the VBScript entry point'
Assert-Contains $setupPackage 'windows_setup_launcher.vbs' 'setup package launches its setup bridge'
Assert-Contains $setupLauncher 'Uninstall GIFT.lnk' 'setup creates a Start Menu uninstall shortcut'
Assert-Contains $setupLauncher 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\gift' 'setup registers the current-user uninstaller'
$uninstaller = Read-RepositoryFile 'tool/windows_uninstall.ps1'
$uninstallBridge = Read-RepositoryFile 'tool/windows_uninstall.vbs'
Assert-Contains $uninstaller 'Remove-ShortcutIfTarget' 'uninstall only removes matching shortcuts'
Assert-Contains $uninstaller 'SkipConfirmation' 'uninstall supports a confirmation-free cleanup handoff'
Assert-Contains $uninstallBridge '-STA' 'uninstall starts PowerShell in STA mode for WinForms'
Assert-Contains $uninstallBridge 'windows_uninstall.ps1' 'uninstall bridge invokes the bundled PowerShell script'

Write-Output 'Windows packaging verification passed: setup wizard and portable launcher are distinct.'
