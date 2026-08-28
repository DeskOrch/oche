$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

dart run benchmarks/harness/bin/build_routing_kernels.dart @args
