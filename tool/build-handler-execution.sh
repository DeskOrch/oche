#!/usr/bin/env sh
set -eu

dart run benchmarks/harness/bin/build_handler_execution.dart "$@"
