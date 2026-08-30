#!/usr/bin/env sh
set -eu

dart run benchmarks/harness/bin/build_middleware_execution.dart "$@"
