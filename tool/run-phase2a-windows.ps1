param(
    [string]$OhaPath = 'oha',
    [string]$ResultsDirectory = 'benchmarks/results/phase2a-windows',
    [string]$ConcurrencySweep = '10,100,500',
    [int]$WarmupSeconds = 5,
    [int]$DurationSeconds = 30,
    [int]$Iterations = 5,
    [int]$CooldownSeconds = 2
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

Push-Location (Join-Path $PSScriptRoot '..')
try {
    Push-Location 'examples/hello_oche'
    try {
        dart run build_runner build
    }
    finally {
        Pop-Location
    }

    dart run benchmarks/harness/bin/build_public_application.dart
    dart run benchmarks/harness/bin/public_api_suite.dart `
        --concurrency-sweep=$ConcurrencySweep `
        --warmup=$WarmupSeconds `
        --duration=$DurationSeconds `
        --iterations=$Iterations `
        --cooldown=$CooldownSeconds `
        --oha=$OhaPath `
        --results-dir=$ResultsDirectory
}
finally {
    Pop-Location
}
