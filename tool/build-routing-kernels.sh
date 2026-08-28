#!/usr/bin/env sh
set -eu

dart run benchmarks/harness/bin/build_routing_kernels.dart "$@"
