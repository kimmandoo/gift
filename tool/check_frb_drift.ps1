$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$codegen = 'C:\Users\USER\.cargo\bin\flutter_rust_bridge_codegen.exe'
$flutterBin = 'C:\Users\USER\flutter\bin'
$generatedFiles = @(
    'lib/src/rust/generated/api.dart',
    'lib/src/rust/generated/frb_generated.dart',
    'lib/src/rust/generated/frb_generated.io.dart',
    'lib/src/rust/generated/frb_generated.web.dart',
    'native/src/frb_generated.rs'
)

Push-Location $repoRoot
try {
    $env:PATH = "$flutterBin;$env:PATH"

    & $codegen generate
    if ($LASTEXITCODE -ne 0) {
        throw "flutter_rust_bridge_codegen exited with $LASTEXITCODE."
    }

    $firstPass = @{}
    foreach ($file in $generatedFiles) {
        $firstPass[$file] = (Get-FileHash -Algorithm SHA256 $file).Hash
    }

    & $codegen generate
    if ($LASTEXITCODE -ne 0) {
        throw "flutter_rust_bridge_codegen exited with $LASTEXITCODE."
    }

    foreach ($file in $generatedFiles) {
        $secondPass = (Get-FileHash -Algorithm SHA256 $file).Hash
        if ($firstPass[$file] -ne $secondPass) {
            throw "FRB generation was not stable for $file."
        }
    }

    & git diff --exit-code -- $generatedFiles
    if ($LASTEXITCODE -ne 0) {
        throw 'FRB generated bindings drift from the committed output.'
    }
} finally {
    Pop-Location
}
