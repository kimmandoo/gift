param(
  [Parameter(Mandatory = $true)]
  [string]$PayloadPath
)

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$state = [pscustomobject]@{
  Page = 'welcome'
  ExitCode = 0
  Installed = $false
  InstallDirectory = Join-Path $env:LOCALAPPDATA 'Programs\gift'
  CreateStartMenu = $true
  CreateDesktop = $true
  CreateShellIntegration = $true
  AddToPath = $true
  LaunchAfterInstall = $true
}

$form = New-Object System.Windows.Forms.Form
$form.Size = [System.Drawing.Size]::new(560, 470)
$form.MinimumSize = [System.Drawing.Size]::new(560, 470)
$form.MaximumSize = [System.Drawing.Size]::new(560, 470)
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
$form.MaximizeBox = $false
$form.MinimizeBox = $false
$form.ShowInTaskbar = $true
$form.Font = [System.Drawing.Font]::new('Segoe UI', 10)
$form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi

$headerLabel = New-Object System.Windows.Forms.Label
$headerLabel.Location = [System.Drawing.Point]::new(24, 18)
$headerLabel.Size = [System.Drawing.Size]::new(500, 34)
$headerLabel.Font = [System.Drawing.Font]::new(
  'Segoe UI',
  16,
  [System.Drawing.FontStyle]::Bold
)
$form.Controls.Add($headerLabel)

$contentPanel.Size = [System.Drawing.Size]::new(500, 320)
$contentPanel.AutoScroll = $true
$form.Controls.Add($contentPanel)
$footerPanel.Location = [System.Drawing.Point]::new(24, 394)
$footerPanel.Size = [System.Drawing.Size]::new(500, 48)
$form.Controls.Add($footerPanel)

$backButton = New-Object System.Windows.Forms.Button
$backButton.Text = '< Back'
$backButton.Location = [System.Drawing.Point]::new(196, 8)
$backButton.Size = [System.Drawing.Size]::new(88, 32)
$footerPanel.Controls.Add($backButton)

$nextButton = New-Object System.Windows.Forms.Button
$nextButton.Text = 'Next >'
$nextButton.Location = [System.Drawing.Point]::new(292, 8)
$nextButton.Size = [System.Drawing.Size]::new(88, 32)
$nextButton.Enabled = $true
$footerPanel.Controls.Add($nextButton)

$cancelButton = New-Object System.Windows.Forms.Button
$cancelButton.Text = 'Cancel'
$cancelButton.Location = [System.Drawing.Point]::new(388, 8)
$cancelButton.Size = [System.Drawing.Size]::new(88, 32)
$footerPanel.Controls.Add($cancelButton)

$welcomePanel = New-Object System.Windows.Forms.Panel
$welcomePanel.Location = [System.Drawing.Point]::new(0, 0)
$welcomePanel.Size = [System.Drawing.Size]::new(476, 250)
$contentPanel.Controls.Add($welcomePanel)

$welcomeTitle = New-Object System.Windows.Forms.Label
$welcomeTitle.Text = 'Install GIFT Git client'
$welcomeTitle.Location = [System.Drawing.Point]::new(8, 10)
$welcomeTitle.Size = [System.Drawing.Size]::new(460, 30)
$welcomeTitle.Font = [System.Drawing.Font]::new(
  'Segoe UI',
  12,
  [System.Drawing.FontStyle]::Bold
)
$welcomePanel.Controls.Add($welcomeTitle)

$welcomeText = New-Object System.Windows.Forms.Label
$welcomeText.Text = 'This wizard installs GIFT for the current Windows user. It keeps the application in a stable folder and can create shortcuts for you.'
$welcomeText.Location = [System.Drawing.Point]::new(8, 52)
$welcomeText.Size = [System.Drawing.Size]::new(460, 58)
$welcomeText.AutoSize = $false
$welcomePanel.Controls.Add($welcomeText)

$welcomeDetails = New-Object System.Windows.Forms.Label
$welcomeDetails.Text = "The portable executable does not install anything. Use this setup package when you want shortcuts, an installed copy, and an uninstall entry."
$welcomeDetails.Location = [System.Drawing.Point]::new(8, 130)
$welcomeDetails.Size = [System.Drawing.Size]::new(460, 64)
$welcomeDetails.AutoSize = $false
$welcomePanel.Controls.Add($welcomeDetails)

$optionsPanel = New-Object System.Windows.Forms.Panel
$optionsPanel.Location = [System.Drawing.Point]::new(0, 0)
$optionsPanel.Size = [System.Drawing.Size]::new(476, 250)
$optionsPanel.Visible = $false
$contentPanel.Controls.Add($optionsPanel)

$optionsPanel.Size = [System.Drawing.Size]::new(476, 300)
$installPathLabel.Text = 'Install location'
$installPathLabel.Location = [System.Drawing.Point]::new(8, 10)
$installPathLabel.Size = [System.Drawing.Size]::new(460, 24)
$optionsPanel.Controls.Add($installPathLabel)

$installPathBox = New-Object System.Windows.Forms.TextBox
$installPathBox.Location = [System.Drawing.Point]::new(8, 38)
$installPathBox.Size = [System.Drawing.Size]::new(350, 28)
$installPathBox.Text = $state.InstallDirectory
$optionsPanel.Controls.Add($installPathBox)

$browseButton = New-Object System.Windows.Forms.Button
$browseButton.Text = 'Browse...'
$browseButton.Location = [System.Drawing.Point]::new(368, 37)
$browseButton.Size = [System.Drawing.Size]::new(100, 30)
$optionsPanel.Controls.Add($browseButton)

$shortcutLabel = New-Object System.Windows.Forms.Label
$shortcutLabel.Text = 'Shortcuts'
$shortcutLabel.Location = [System.Drawing.Point]::new(8, 82)
$shortcutLabel.Size = [System.Drawing.Size]::new(460, 24)
$optionsPanel.Controls.Add($shortcutLabel)

$startMenuCheck = New-Object System.Windows.Forms.CheckBox
$startMenuCheck.Text = 'Create a Start Menu shortcut'
$startMenuCheck.Location = [System.Drawing.Point]::new(8, 110)
$startMenuCheck.Size = [System.Drawing.Size]::new(460, 28)
$startMenuCheck.Checked = $true
$optionsPanel.Controls.Add($startMenuCheck)

$desktopCheck = New-Object System.Windows.Forms.CheckBox
$desktopCheck.Text = 'Create a Desktop shortcut'
$desktopCheck.Location = [System.Drawing.Point]::new(8, 142)
$desktopCheck.Size = [System.Drawing.Size]::new(460, 28)
$desktopCheck.Checked = $true
$optionsPanel.Controls.Add($desktopCheck)

$optionsNote = New-Object System.Windows.Forms.Label
$optionsNote.Text = 'The installer does not require administrator access. Git remains a separate system dependency.'
$optionsNote.Location = [System.Drawing.Point]::new(8, 244)
$shellIntegrationCheck = New-Object System.Windows.Forms.CheckBox
$shellIntegrationCheck.Text = 'Add Explorer "Open with GIFT" entries'
$shellIntegrationCheck.Location = [System.Drawing.Point]::new(8, 174)
$shellIntegrationCheck.Size = [System.Drawing.Size]::new(460, 28)
$shellIntegrationCheck.Checked = $true
$optionsPanel.Controls.Add($shellIntegrationCheck)

$pathCheck = New-Object System.Windows.Forms.CheckBox
$pathCheck.Text = 'Add GIFT to my user PATH'
$pathCheck.Location = [System.Drawing.Point]::new(8, 206)
$pathCheck.Size = [System.Drawing.Size]::new(460, 28)
$pathCheck.Checked = $true
$optionsPanel.Controls.Add($pathCheck)
$optionsNote.Size = [System.Drawing.Size]::new(460, 42)
$optionsNote.AutoSize = $false
$optionsPanel.Controls.Add($optionsNote)

$completePanel = New-Object System.Windows.Forms.Panel
$completePanel.Location = [System.Drawing.Point]::new(0, 0)
$completePanel.Size = [System.Drawing.Size]::new(476, 250)
$completePanel.Visible = $false
$contentPanel.Controls.Add($completePanel)

$completeTitle = New-Object System.Windows.Forms.Label
$completeTitle.Text = 'Installation complete'
$completeTitle.Location = [System.Drawing.Point]::new(8, 10)
$completeTitle.Size = [System.Drawing.Size]::new(460, 30)
$completeTitle.Font = [System.Drawing.Font]::new(
  'Segoe UI',
  12,
  [System.Drawing.FontStyle]::Bold
)
$completePanel.Controls.Add($completeTitle)

$completeDetails = New-Object System.Windows.Forms.Label
$completeDetails.Location = [System.Drawing.Point]::new(8, 54)
$completeDetails.Size = [System.Drawing.Size]::new(460, 80)
$completeDetails.AutoSize = $false
$completePanel.Controls.Add($completeDetails)

$launchCheck = New-Object System.Windows.Forms.CheckBox
$launchCheck.Text = 'Launch GIFT when I click Finish'
$launchCheck.Location = [System.Drawing.Point]::new(8, 160)
$launchCheck.Size = [System.Drawing.Size]::new(460, 28)
$launchCheck.Checked = $true
$completePanel.Controls.Add($launchCheck)

function Set-Page([string]$page) {
  $state.Page = $page
  $welcomePanel.Visible = $page -eq 'welcome'
  $optionsPanel.Visible = $page -eq 'options'
  $completePanel.Visible = $page -eq 'complete'
  $backButton.Visible = $page -eq 'options'
  $backButton.Enabled = $page -eq 'options'

  switch ($page) {
    'welcome' {
      $headerLabel.Text = 'Welcome to GIFT Setup'
      $nextButton.Text = 'Next >'
      $nextButton.Enabled = $true
      $cancelButton.Text = 'Cancel'
    }
    'options' {
      $headerLabel.Text = 'Choose install options'
      $nextButton.Text = 'Install'
      $nextButton.Enabled = $true
      $cancelButton.Text = 'Cancel'
    }
    'complete' {
      $headerLabel.Text = 'GIFT is ready'
      $nextButton.Text = 'Finish'
      $nextButton.Enabled = $true
      $cancelButton.Visible = $false
    }
  }
}

function New-GiftShortcut(
  [string]$ShortcutPath,
  [string]$ApplicationPath,
  [string]$WorkingDirectory,
  [string]$Arguments = ''
) {
  $shortcutDirectory = Split-Path -Parent $ShortcutPath
  New-Item -ItemType Directory -Path $shortcutDirectory -Force | Out-Null
  $shell = New-Object -ComObject WScript.Shell
  $shortcut = $shell.CreateShortcut($ShortcutPath)

  $shortcut.TargetPath = $ApplicationPath
  $shortcut.WorkingDirectory = $WorkingDirectory
  if (-not [string]::IsNullOrWhiteSpace($Arguments)) {
    $shortcut.Arguments = $Arguments
  }
  $shortcut.IconLocation = "$ApplicationPath,0"
  $shortcut.Description = 'Launch GIFT Git client'
  $shortcut.Save()
}
function Set-GiftShellIntegration([string]$ApplicationPath) {
  $directoryKey = 'HKCU:\Software\Classes\Directory\shell\GIFT'
  $backgroundKey = 'HKCU:\Software\Classes\Directory\Background\shell\GIFT'
  $entries = @(
    @($directoryKey, '"{0}" "%1"' -f $ApplicationPath),
    @($backgroundKey, '"{0}" "%V"' -f $ApplicationPath)
  )
  foreach ($entry in $entries) {
    $keyPath = $entry[0]
    $commandPath = Join-Path $keyPath 'command'
    New-Item -Path $commandPath -Force | Out-Null
    Set-ItemProperty -Path $keyPath -Name '(default)' -Value 'Open with GIFT'
    Set-ItemProperty -Path $commandPath -Name '(default)' -Value $entry[1]
  }
}

function Add-GiftUserPath([string]$InstallDirectory) {
  $environmentKey = 'HKCU:\Environment'
  New-Item -Path $environmentKey -Force | Out-Null
  $currentPath = (Get-ItemProperty -Path $environmentKey -Name 'Path' -ErrorAction SilentlyContinue).Path
  $entries = @(
    @($currentPath -split ';') |
      ForEach-Object { $_.Trim() } |
      Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
  )
  $normalizedInstall = $InstallDirectory.TrimEnd('\')
  if (-not ($entries | Where-Object { $_.TrimEnd('\') -ieq $normalizedInstall })) {
    Set-ItemProperty -Path $environmentKey -Name 'Path' -Value (($entries + $InstallDirectory) -join ';')
  }
}

function Install-Gift {
  $extractDirectory = $null
  try {
    $installDirectory = $installPathBox.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($installDirectory)) {
      throw 'Choose an install location before continuing.'
    }

    $payload = (Resolve-Path -LiteralPath $PayloadPath).Path
    $packageDirectory = Split-Path -Parent $payload
    $extractDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ('gift-setup-' + [guid]::NewGuid().ToString('N'))
    $applicationPath = Join-Path $installDirectory 'gift.exe'
    $startMenuDirectory = Join-Path ([Environment]::GetFolderPath('StartMenu')) 'Programs\gift'
    $startMenuShortcutPath = Join-Path $startMenuDirectory 'gift.lnk'
    $uninstallShortcutPath = Join-Path $startMenuDirectory 'Uninstall GIFT.lnk'
    $desktopDirectory = [Environment]::GetFolderPath('Desktop')
    $desktopShortcutPath = Join-Path $desktopDirectory 'gift.lnk'
    $wscript = Join-Path $env:WINDIR 'System32\wscript.exe'
    $uninstallScript = Join-Path $installDirectory 'Uninstall-Gift.ps1'
    $uninstallVbs = Join-Path $installDirectory 'Uninstall-Gift.vbs'
    $uninstallShortcutArguments = '"' + $uninstallVbs + '"'

    New-Item -ItemType Directory -Path $extractDirectory -Force | Out-Null
    Expand-Archive -LiteralPath $payload -DestinationPath $extractDirectory -Force
    $extractedApplication = Join-Path $extractDirectory 'gift.exe'
    if (-not (Test-Path -LiteralPath $extractedApplication -PathType Leaf)) {
      throw 'The Windows setup package did not contain gift.exe.'
    }

    Get-Process -Name 'gift' -ErrorAction SilentlyContinue |
      Stop-Process -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $installDirectory) {
      Remove-Item -LiteralPath $installDirectory -Recurse -Force
    }
    New-Item -ItemType Directory -Path $installDirectory -Force | Out-Null
    Get-ChildItem -LiteralPath $extractDirectory -Force | ForEach-Object {
      Copy-Item -LiteralPath $_.FullName -Destination $installDirectory -Recurse -Force
    }
    if ($shellIntegrationCheck.Checked) {
      Set-GiftShellIntegration $applicationPath
    }
    if ($pathCheck.Checked) {
      Add-GiftUserPath $installDirectory
    }

    Copy-Item -LiteralPath (Join-Path $packageDirectory 'Uninstall-Gift.ps1') -Destination $uninstallScript -Force
    Copy-Item -LiteralPath (Join-Path $packageDirectory 'Uninstall-Gift.vbs') -Destination $uninstallVbs -Force

    if ($startMenuCheck.Checked) {
      New-GiftShortcut $startMenuShortcutPath $applicationPath $installDirectory
      New-GiftShortcut `
        $uninstallShortcutPath `
        $wscript `
        $installDirectory `
        $uninstallShortcutArguments
    } else {
      Remove-Item -LiteralPath $startMenuShortcutPath -Force -ErrorAction SilentlyContinue
      Remove-Item -LiteralPath $uninstallShortcutPath -Force -ErrorAction SilentlyContinue
    }
    if ($desktopCheck.Checked) {
      New-GiftShortcut $desktopShortcutPath $applicationPath $installDirectory
    } else {
      Remove-Item -LiteralPath $desktopShortcutPath -Force -ErrorAction SilentlyContinue
    }

    $uninstallKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\gift'
    New-Item -Path $uninstallKey -Force | Out-Null
    Set-ItemProperty -Path $uninstallKey -Name 'DisplayName' -Value 'GIFT'
    Set-ItemProperty -Path $uninstallKey -Name 'DisplayVersion' -Value '1.0.0'
    Set-ItemProperty -Path $uninstallKey -Name 'Publisher' -Value 'kimmandoo'
    Set-ItemProperty -Path $uninstallKey -Name 'InstallLocation' -Value $installDirectory
    Set-ItemProperty -Path $uninstallKey -Name 'DisplayIcon' -Value $applicationPath
    Set-ItemProperty -Path $uninstallKey -Name 'UninstallString' -Value ('wscript.exe "{0}"' -f $uninstallVbs)
    Set-ItemProperty -Path $uninstallKey -Name 'ShellIntegration' -Value ([int]$shellIntegrationCheck.Checked)
    Set-ItemProperty -Path $uninstallKey -Name 'PathIntegration' -Value ([int]$pathCheck.Checked)

    $state.InstallDirectory = $installDirectory
    $state.LaunchAfterInstall = $launchCheck.Checked
    $state.Installed = $true
    $completeDetails.Text = "GIFT was installed in:`r`n$installDirectory`r`n`r`nUse the shortcuts to launch it any time."
    Set-Page 'complete'
  } catch {
    [System.Windows.Forms.MessageBox]::Show(
      $form,
      $_.Exception.Message,
      'GIFT Setup',
      [System.Windows.Forms.MessageBoxButtons]::OK,
      [System.Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
    $nextButton.Enabled = $true
    $backButton.Enabled = $true
  } finally {
    if ($extractDirectory -and (Test-Path -LiteralPath $extractDirectory)) {
      Remove-Item -LiteralPath $extractDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
}

$browseButton.Add_Click({
  $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
  $dialog.Description = 'Choose where GIFT should be installed.'
  $dialog.SelectedPath = $installPathBox.Text
  if ($dialog.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
    $installPathBox.Text = $dialog.SelectedPath
  }
  $dialog.Dispose()
})

$backButton.Add_Click({
  Set-Page 'welcome'
})

$nextButton.Add_Click({
  if ($state.Page -eq 'welcome') {
    Set-Page 'options'
    return
  }
  if ($state.Page -eq 'options') {
    $state.CreateStartMenu = $startMenuCheck.Checked
    $state.CreateDesktop = $desktopCheck.Checked
    $state.CreateShellIntegration = $shellIntegrationCheck.Checked
    $state.AddToPath = $pathCheck.Checked
    $nextButton.Enabled = $false
    $backButton.Enabled = $false
    [System.Windows.Forms.Application]::DoEvents()
    Install-Gift
    return
  }
  if ($state.Page -eq 'complete') {
    if ($state.LaunchAfterInstall) {
      Start-Process -FilePath (Join-Path $state.InstallDirectory 'gift.exe') -WorkingDirectory $state.InstallDirectory
    }
    $form.Close()
  }
})

$cancelButton.Add_Click({
  $form.Close()
})

$form.Add_Shown({
  $form.Activate()
})

Set-Page 'welcome'
[void]$form.ShowDialog()
exit $state.ExitCode
