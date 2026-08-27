param(
    [string]$OhaPath = 'oha',
    [string]$ResultsDirectory = 'benchmarks/results/phase06-windows'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

./tool/build_benchmarks.ps1
dart run benchmarks/harness/bin/suite.dart `
    --mode=aot `
    --host=127.0.0.1 `
    --port=8080 `
    --concurrency-sweep=10,100,500 `
    --warmup=5 `
    --duration=30 `
    --iterations=5 `
    --cooldown=2 `
    --load-generator=oha `
    --oha=$OhaPath `
    --results-dir=$ResultsDirectory
