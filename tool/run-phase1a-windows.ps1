param(
    [string]$OhaPath = 'oha',
    [string]$ResultsDirectory = 'benchmarks/results/phase1a-windows',
    [string]$WorkloadSets = 'success,error',
    [string]$ConcurrencySweep = '10,100,500',
    [int]$WarmupSeconds = 5,
    [int]$DurationSeconds = 30,
    [int]$Iterations = 5,
    [int]$CooldownSeconds = 2
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

& "$PSScriptRoot/build-routing-kernels.ps1"
dart run benchmarks/harness/bin/routing_kernel_suite.dart `
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
