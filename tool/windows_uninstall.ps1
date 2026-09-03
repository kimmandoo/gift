$ErrorActionPreference = 'SilentlyContinue'
$installDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$startMenuDirectory = Join-Path ([Environment]::GetFolderPath('StartMenu')) 'Programs\gift'
$startMenuShortcutPath = Join-Path $startMenuDirectory 'gift.lnk'
$desktopDirectory = [Environment]::GetFolderPath('Desktop')
$desktopShortcutPath = Join-Path $desktopDirectory 'gift.lnk'
$uninstallKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\gift'

Get-Process -Name 'gift' -ErrorAction SilentlyContinue | Stop-Process -Force
Remove-Item -LiteralPath $startMenuShortcutPath -Force
Remove-Item -LiteralPath $startMenuDirectory -Force
Remove-Item -LiteralPath $desktopShortcutPath -Force
Remove-Item -Path $uninstallKey -Recurse -Force
Remove-Item -LiteralPath $installDirectory -Recurse -Force
