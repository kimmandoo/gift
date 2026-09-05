$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repositoryRoot

$releaseTag = $env:GIFT_RELEASE_TAG
if ([string]::IsNullOrWhiteSpace($releaseTag) -or $releaseTag -notmatch '^release-v[0-9]+\.[0-9]+\.[0-9]+([-.][0-9A-Za-z.-]+)?$') {
    throw 'GIFT_RELEASE_TAG must be a release-v<semver> tag.'
}
$version = $releaseTag.Substring('release-v'.Length)
$outputDirectory = if ([string]::IsNullOrWhiteSpace($env:GIFT_RELEASE_OUTPUT_DIR)) { 'dist' } else { $env:GIFT_RELEASE_OUTPUT_DIR }
New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null

$stage = Join-Path $repositoryRoot 'build\release-stage\windows'
if (Test-Path -LiteralPath $stage) {
    Remove-Item -LiteralPath $stage -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $stage | Out-Null
Copy-Item -LiteralPath 'build\windows\x64\runner\Release' -Destination (Join-Path $stage 'Release') -Recurse
Copy-Item -LiteralPath 'build\windows\x64\runner\gift-portable.exe' -Destination $stage
Copy-Item -LiteralPath 'build\windows\x64\runner\gift-setup.exe' -Destination $stage

$archive = Join-Path $outputDirectory "gift-$version-windows-x64.zip"
if (Test-Path -LiteralPath $archive) {
    Remove-Item -LiteralPath $archive -Force
}
Compress-Archive -Path (Join-Path $stage 'Release'), (Join-Path $stage 'gift-portable.exe'), (Join-Path $stage 'gift-setup.exe') -DestinationPath $archive -CompressionLevel Optimal
Write-Output "Windows release archive: $archive"
