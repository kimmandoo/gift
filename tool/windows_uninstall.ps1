param(
  [string]$RemovePath,
  [switch]$SkipConfirmation
)

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms

function Show-UninstallMessage(
  [string]$Message,
  [string]$Title,
  [System.Windows.Forms.MessageBoxButtons]$Buttons,
  [System.Windows.Forms.MessageBoxIcon]$Icon
) {
  [System.Windows.Forms.MessageBox]::Show(
    $Message,
    $Title,
    $Buttons,
    $Icon
  ) | Out-Null
}

function Quote-Argument([string]$Value) {
  '"' + $Value.Replace('"', '\"') + '"'
}

function Remove-ShortcutIfTarget(
  [string]$Path,
  [string]$Target,
  [string]$Arguments = ''
) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    return
  }
  try {
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($Path)
    $targetMatches = $shortcut.TargetPath -ieq $Target
    $argumentsMatch = [string]::IsNullOrWhiteSpace($Arguments) -or
      $shortcut.Arguments.Trim('" ') -ieq $Arguments.Trim('" ')
    if ($targetMatches -and $argumentsMatch) {
      Remove-Item -LiteralPath $Path -Force
    }
  } catch {
    # A stale or inaccessible shortcut must not block uninstall.
  }
}

$scriptPath = [System.IO.Path]::GetFullPath($MyInvocation.MyCommand.Definition)
$installDirectory = if ([string]::IsNullOrWhiteSpace($RemovePath)) {
  Split-Path -Parent $scriptPath
} else {
  [System.IO.Path]::GetFullPath($RemovePath)
}
$startMenuDirectory = Join-Path ([Environment]::GetFolderPath('StartMenu')) 'Programs\gift'
$startMenuShortcutPath = Join-Path $startMenuDirectory 'gift.lnk'
$uninstallShortcutPath = Join-Path $startMenuDirectory 'Uninstall GIFT.lnk'
$desktopShortcutPath = Join-Path ([Environment]::GetFolderPath('Desktop')) 'gift.lnk'
$uninstallKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\gift'
$wscript = Join-Path $env:WINDIR 'System32\wscript.exe'
$uninstaller = Join-Path $installDirectory 'windows_uninstall.vbs'
$applicationPath = Join-Path $installDirectory 'gift.exe'

if ([string]::IsNullOrWhiteSpace($RemovePath)) {
  if (-not (Test-Path -LiteralPath $installDirectory -PathType Container) -or
      -not (Test-Path -LiteralPath $applicationPath -PathType Leaf)) {
    Show-UninstallMessage `
      'GIFT is not installed at the expected location.' `
      'GIFT Uninstall' `
      ([System.Windows.Forms.MessageBoxButtons]::OK) `
      ([System.Windows.Forms.MessageBoxIcon]::Information)
    exit 0
  }

  if (-not $SkipConfirmation) {
    $answer = [System.Windows.Forms.MessageBox]::Show(
      'Remove GIFT and its installed files?',
      'GIFT Uninstall',
      [System.Windows.Forms.MessageBoxButtons]::YesNo,
      [System.Windows.Forms.MessageBoxIcon]::Question
    )
    if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) {
      exit 0
    }
  }

  $temporaryScript = Join-Path $env:TEMP (
    'gift-uninstall-' + [guid]::NewGuid().ToString('N') + '.ps1'
  )
  Copy-Item -LiteralPath $scriptPath -Destination $temporaryScript -Force
  $arguments = @(
    '-NoProfile',
    '-ExecutionPolicy',
    'Bypass',
    '-WindowStyle',
    'Hidden',
    '-File',
    (Quote-Argument $temporaryScript),
    '-RemovePath',
    (Quote-Argument $installDirectory),
    '-SkipConfirmation'
  ) -join ' '
  Start-Process -FilePath 'powershell.exe' `
    -ArgumentList $arguments `
    -WorkingDirectory $env:TEMP `
    -WindowStyle Hidden
  exit 0
}

try {
  Get-Process -Name 'gift' -ErrorAction SilentlyContinue | ForEach-Object {
    try {
      if ($_.Path -ieq $applicationPath) {
        $_.CloseMainWindow() | Out-Null
        Start-Sleep -Milliseconds 500
        if (-not $_.HasExited) {
          $_.Kill()
        }
      }
    } catch {
      # A process that already exited needs no further action.
    }
  }

  Remove-ShortcutIfTarget `
    -Path $startMenuShortcutPath `
    -Target $applicationPath
  Remove-ShortcutIfTarget `
    -Path $uninstallShortcutPath `
    -Target $wscript `
    -Arguments $uninstaller
  Remove-ShortcutIfTarget `
    -Path $desktopShortcutPath `
    -Target $applicationPath

  if (Test-Path -LiteralPath $uninstallKey) {
    $registeredInstallPath = (
      Get-ItemProperty -LiteralPath $uninstallKey `
        -Name 'InstallLocation' `
        -ErrorAction SilentlyContinue
    ).InstallLocation
    if ([string]::IsNullOrWhiteSpace($registeredInstallPath) -or
        $registeredInstallPath -ieq $installDirectory) {
      Remove-Item -LiteralPath $uninstallKey -Recurse -Force
    }
  }

  if (Test-Path -LiteralPath $installDirectory) {
    Remove-Item -LiteralPath $installDirectory -Recurse -Force
  }

  if ((Test-Path -LiteralPath $startMenuDirectory -PathType Container) -and
      -not (Get-ChildItem -LiteralPath $startMenuDirectory -Force)) {
    Remove-Item -LiteralPath $startMenuDirectory -Force
  }

  Show-UninstallMessage `
    'GIFT was uninstalled successfully.' `
    'GIFT Uninstall' `
    ([System.Windows.Forms.MessageBoxButtons]::OK) `
    ([System.Windows.Forms.MessageBoxIcon]::Information)
} catch {
  Show-UninstallMessage `
    ("GIFT could not be uninstalled.`n`n{0}" -f $_.Exception.Message) `
    'GIFT Uninstall' `
    ([System.Windows.Forms.MessageBoxButtons]::OK) `
    ([System.Windows.Forms.MessageBoxIcon]::Error)
  exit 1
} finally {
  if ($RemovePath) {
    Remove-Item -LiteralPath $scriptPath -Force -ErrorAction SilentlyContinue
  }
}
