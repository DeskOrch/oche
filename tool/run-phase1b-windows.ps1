param(
    [string]$OhaPath = 'oha',
    [string]$ResultsDirectory = 'benchmarks/results/phase1b-windows',
    [string]$WorkloadSets = 'sync,async',
    [string]$ConcurrencySweep = '10,100,500',
    [int]$WarmupSeconds = 5,
    [int]$DurationSeconds = 30,
    [int]$Iterations = 5,
    [int]$CooldownSeconds = 2
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

& "$PSScriptRoot/build-handler-execution.ps1"
& "build/handler_execution/execution_microbenchmark.exe" `
    --calls=5000000 `
    --warmup-calls=500000 `
    --iterations=5 `
    --output="$ResultsDirectory/phase1b-handler-micro-windows-aot.json"
dart run benchmarks/harness/bin/handler_execution_suite.dart `
    --mode=aot `
    --route-counts=10,100,1000 `
    --concurrency-sweep=$ConcurrencySweep `
    --warmup=$WarmupSeconds `
    --duration=$DurationSeconds `
    --iterations=$Iterations `
    --cooldown=$CooldownSeconds `
    --workload-sets=$WorkloadSets `
    --oha=$OhaPath `
    --results-dir=$ResultsDirectory
