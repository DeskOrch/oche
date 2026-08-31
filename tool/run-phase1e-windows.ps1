param(
    [string]$OhaPath = 'oha',
    [string]$ResultsDirectory = 'benchmarks/results/phase1e-windows',
    [string]$ConcurrencySweep = '10,100,500',
    [int]$WarmupSeconds = 5,
    [int]$DurationSeconds = 30,
    [int]$Iterations = 5,
    [int]$CooldownSeconds = 2
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

& "$PSScriptRoot/build-middleware-execution.ps1"

dart run benchmarks/harness/bin/middleware_execution_suite.dart `
    --mode=aot `
    --route-counts=100 `
    --middleware-depths=3 `
    --concurrency-sweep=$ConcurrencySweep `
    --warmup=$WarmupSeconds `
    --duration=$DurationSeconds `
    --iterations=$Iterations `
    --cooldown=$CooldownSeconds `
    --workload-sets=lifecycle `
    --oha=$OhaPath `
    --results-dir=$ResultsDirectory

dart run benchmarks/harness/bin/benchmark.dart `
    --implementation=response_lifecycle `
    --mode=aot `
    --endpoint=/stream `
    --readiness-endpoint=/health `
    --expected-status=200 `
    --route-count=100 `
    --middleware-depth=3 `
    --middleware-profile=streaming `
    --workload=streaming_three_chunk `
    --concurrency=10 `
    --warmup=$WarmupSeconds `
    --duration=$DurationSeconds `
    --oha=$OhaPath `
    --executable=build/middleware_execution/response_lifecycle_r100_d3.exe `
    --generated-source=benchmarks/handler_execution/generated_middleware/lifecycle_r100_d3.dart `
    --output=$ResultsDirectory/phase1e-streaming-windows-aot.json
