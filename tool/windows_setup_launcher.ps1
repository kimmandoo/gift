param(
  [Parameter(Mandatory = $true)]
  [string]$PayloadPath
)

$ErrorActionPreference = 'Stop'
$installDirectory = Join-Path $env:LOCALAPPDATA 'Programs\gift'
$extractDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ('gift-setup-' + [guid]::NewGuid().ToString('N'))
$packageDirectory = Split-Path -Parent $PayloadPath
$applicationPath = Join-Path $installDirectory 'gift.exe'
$startMenuDirectory = Join-Path ([Environment]::GetFolderPath('StartMenu')) 'Programs\gift'
$shortcutPath = Join-Path $startMenuDirectory 'gift.lnk'
$uninstallScript = Join-Path $installDirectory 'windows_uninstall.ps1'
$uninstallVbs = Join-Path $installDirectory 'windows_uninstall.vbs'

try {
  New-Item -ItemType Directory -Path $extractDirectory -Force | Out-Null
  Expand-Archive -LiteralPath $PayloadPath -DestinationPath $extractDirectory -Force
  $extractedApplication = Join-Path $extractDirectory 'gift.exe'
  if (-not (Test-Path -LiteralPath $extractedApplication -PathType Leaf)) {
    throw 'The Windows setup package did not contain gift.exe.'
  }

  Get-Process -Name 'gift' -ErrorAction SilentlyContinue | Stop-Process -Force
  if (Test-Path -LiteralPath $installDirectory) {
    Remove-Item -LiteralPath $installDirectory -Recurse -Force
  }
  New-Item -ItemType Directory -Path $installDirectory -Force | Out-Null
  Get-ChildItem -LiteralPath $extractDirectory -Force | Copy-Item -Destination $installDirectory -Recurse -Force
  Copy-Item -LiteralPath (Join-Path $packageDirectory 'windows_uninstall.ps1') -Destination $uninstallScript -Force
  Copy-Item -LiteralPath (Join-Path $packageDirectory 'windows_uninstall.vbs') -Destination $uninstallVbs -Force

  New-Item -ItemType Directory -Path $startMenuDirectory -Force | Out-Null
  $shell = New-Object -ComObject WScript.Shell
  $shortcut = $shell.CreateShortcut($shortcutPath)
  $shortcut.TargetPath = $applicationPath
  $shortcut.WorkingDirectory = $installDirectory
  $shortcut.Description = 'Launch gift Git client'
  $shortcut.Save()

  $uninstallKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\gift'
  New-Item -Path $uninstallKey -Force | Out-Null
  Set-ItemProperty -Path $uninstallKey -Name 'DisplayName' -Value 'gift'
  Set-ItemProperty -Path $uninstallKey -Name 'DisplayVersion' -Value '1.0.0'
  Set-ItemProperty -Path $uninstallKey -Name 'Publisher' -Value 'kimmandoo'
  Set-ItemProperty -Path $uninstallKey -Name 'InstallLocation' -Value $installDirectory
  Set-ItemProperty -Path $uninstallKey -Name 'DisplayIcon' -Value $applicationPath
  Set-ItemProperty -Path $uninstallKey -Name 'UninstallString' -Value ('wscript.exe "{0}"' -f $uninstallVbs)

  Start-Process -FilePath $applicationPath -WorkingDirectory $installDirectory
} catch {
  Write-Error $_
  exit 1
} finally {
  if (Test-Path -LiteralPath $extractDirectory) {
    Remove-Item -LiteralPath $extractDirectory -Recurse -Force -ErrorAction SilentlyContinue
  }
}
