$ErrorActionPreference = 'SilentlyContinue'
$installDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$startMenuDirectory = Join-Path ([Environment]::GetFolderPath('StartMenu')) 'Programs\gift'
$shortcutPath = Join-Path $startMenuDirectory 'gift.lnk'
$uninstallKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\gift'

Get-Process -Name 'gift' -ErrorAction SilentlyContinue | Stop-Process -Force
Remove-Item -LiteralPath $shortcutPath -Force
Remove-Item -LiteralPath $startMenuDirectory -Force
Remove-Item -Path $uninstallKey -Recurse -Force
Remove-Item -LiteralPath $installDirectory -Recurse -Force
