#!/usr/bin/env sh
set -eu

PHASE1A_OHA_PATH="${PHASE1A_OHA_PATH:-oha}"
PHASE1A_RESULTS_DIR="${PHASE1A_RESULTS_DIR:-benchmarks/results/phase1a-linux}"
PHASE1A_WORKLOAD_SETS="${PHASE1A_WORKLOAD_SETS:-success,error}"

sh tool/build-routing-kernels.sh
dart run benchmarks/harness/bin/routing_kernel_suite.dart \
  --mode=aot \
  --route-counts=10,100,1000 \
  --concurrency-sweep="${PHASE1A_CONCURRENCY_SWEEP:-10,100,500}" \
  --warmup="${PHASE1A_WARMUP_SECONDS:-5}" \
  --duration="${PHASE1A_DURATION_SECONDS:-30}" \
  --iterations="${PHASE1A_ITERATIONS:-5}" \
  --cooldown="${PHASE1A_COOLDOWN_SECONDS:-2}" \
  --workload-sets="$PHASE1A_WORKLOAD_SETS" \
  --oha="$PHASE1A_OHA_PATH" \
  --results-dir="$PHASE1A_RESULTS_DIR"
