$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

dart run benchmarks/harness/bin/build_middleware_execution.dart @args
