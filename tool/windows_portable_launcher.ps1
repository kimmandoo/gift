param(
  [Parameter(Mandatory = $true)]
  [string]$PayloadPath
)

$ErrorActionPreference = 'Stop'
$extractDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ('gift-portable-' + [guid]::NewGuid().ToString('N'))

try {
  New-Item -ItemType Directory -Path $extractDirectory -Force | Out-Null
  Expand-Archive -LiteralPath $PayloadPath -DestinationPath $extractDirectory -Force

  $applicationPath = Join-Path $extractDirectory 'gift.exe'
  if (-not (Test-Path -LiteralPath $applicationPath -PathType Leaf)) {
    throw 'The portable package did not contain gift.exe.'
  }

  $process = Start-Process -FilePath $applicationPath -WorkingDirectory $extractDirectory -Wait -PassThru
  exit $process.ExitCode
} catch {
  Write-Error $_
  exit 1
} finally {
  if (Test-Path -LiteralPath $extractDirectory) {
    Remove-Item -LiteralPath $extractDirectory -Recurse -Force -ErrorAction SilentlyContinue
  }
}
