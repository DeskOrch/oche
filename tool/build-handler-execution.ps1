$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

dart run benchmarks/harness/bin/build_handler_execution.dart @args
