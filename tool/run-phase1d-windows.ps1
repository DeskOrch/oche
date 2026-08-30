param(
    [string]$OhaPath = 'oha',
    [string]$ResultsDirectory = 'benchmarks/results/phase1d-windows',
    [string]$WorkloadSets = 'sync,async,short,error,state',
    [string]$MiddlewareDepths = '0,1,3,5,10',
    [string]$ConcurrencySweep = '10,100,500',
    [string]$Implementations = '',
    [int]$WarmupSeconds = 5,
    [int]$DurationSeconds = 30,
    [int]$Iterations = 5,
    [int]$CooldownSeconds = 2
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

& "$PSScriptRoot/build-middleware-execution.ps1"
& "build/middleware_execution/middleware_microbenchmark.exe" `
    --calls=5000000 `
    --warmup-calls=500000 `
    --iterations=5 `
    --output="$ResultsDirectory/phase1d-middleware-micro-windows-aot.json"

$suiteArguments = @(
    'run',
    'benchmarks/harness/bin/middleware_execution_suite.dart',
    '--mode=aot',
    '--route-counts=100',
    "--middleware-depths=$MiddlewareDepths",
    "--concurrency-sweep=$ConcurrencySweep",
    "--warmup=$WarmupSeconds",
    "--duration=$DurationSeconds",
    "--iterations=$Iterations",
    "--cooldown=$CooldownSeconds",
    "--workload-sets=$WorkloadSets",
    "--oha=$OhaPath",
    "--results-dir=$ResultsDirectory"
)
if ($Implementations) {
    $suiteArguments += "--implementations=$Implementations"
}
dart @suiteArguments
