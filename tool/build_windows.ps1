$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repositoryRoot

dart run tool/build_desktop.dart windows
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
