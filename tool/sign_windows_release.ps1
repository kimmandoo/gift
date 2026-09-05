$ErrorActionPreference = 'Stop'

$certificateBase64 = $env:WINDOWS_CERTIFICATE_BASE64
$certificatePassword = $env:WINDOWS_CERTIFICATE_PASSWORD
if ([string]::IsNullOrWhiteSpace($certificateBase64)) {
    throw 'WINDOWS_CERTIFICATE_BASE64 is required for a public release.'
}
if ([string]::IsNullOrWhiteSpace($certificatePassword)) {
    throw 'WINDOWS_CERTIFICATE_PASSWORD is required for a public release.'
}

$repositoryRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repositoryRoot
$certificatePath = Join-Path $env:RUNNER_TEMP 'gift-signing.pfx'
[IO.File]::WriteAllBytes($certificatePath, [Convert]::FromBase64String($certificateBase64))
try {
    $signTool = Get-ChildItem -Path (Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin\*\x64\signtool.exe') |
        Sort-Object FullName |
        Select-Object -Last 1
    if ($null -eq $signTool) {
        throw 'Windows SDK signtool.exe was not found on the runner.'
    }

    $timestampUrl = if ([string]::IsNullOrWhiteSpace($env:WINDOWS_TIMESTAMP_URL)) {
        'http://timestamp.digicert.com'
    } else {
        $env:WINDOWS_TIMESTAMP_URL
    }
    $files = @(
        'build\windows\x64\runner\Release\gift.exe',
        'build\windows\x64\runner\gift-portable.exe',
        'build\windows\x64\runner\gift-setup.exe'
    )
    foreach ($file in $files) {
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
            throw "Windows release executable does not exist: $file"
        }
        & $signTool.FullName sign /fd SHA256 /td SHA256 /tr $timestampUrl /f $certificatePath /p $certificatePassword /d 'GIFT' $file
        if ($LASTEXITCODE -ne 0) {
            throw "signtool failed for $file with exit code $LASTEXITCODE"
        }
        & $signTool.FullName verify /pa /all $file
        if ($LASTEXITCODE -ne 0) {
            throw "signtool verification failed for $file with exit code $LASTEXITCODE"
        }
    }
    Write-Output 'Signed and verified Windows release executables.'
} finally {
    Remove-Item -LiteralPath $certificatePath -Force -ErrorAction SilentlyContinue
}
