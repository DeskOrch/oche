#!/usr/bin/env sh
set -eu

PHASE1B_OHA_PATH="${PHASE1B_OHA_PATH:-oha}"
PHASE1B_RESULTS_DIR="${PHASE1B_RESULTS_DIR:-benchmarks/results/phase1b-linux}"
PHASE1B_WORKLOAD_SETS="${PHASE1B_WORKLOAD_SETS:-sync,async}"

sh tool/build-handler-execution.sh
build/handler_execution/execution_microbenchmark \
  --calls=5000000 \
  --warmup-calls=500000 \
  --iterations=5 \
  --output="$PHASE1B_RESULTS_DIR/phase1b-handler-micro-linux-aot.json"
dart run benchmarks/harness/bin/handler_execution_suite.dart \
  --mode=aot \
  --route-counts=10,100,1000 \
  --concurrency-sweep="${PHASE1B_CONCURRENCY_SWEEP:-10,100,500}" \
  --warmup="${PHASE1B_WARMUP_SECONDS:-5}" \
  --duration="${PHASE1B_DURATION_SECONDS:-30}" \
  --iterations="${PHASE1B_ITERATIONS:-5}" \
  --cooldown="${PHASE1B_COOLDOWN_SECONDS:-2}" \
  --workload-sets="$PHASE1B_WORKLOAD_SETS" \
  --oha="$PHASE1B_OHA_PATH" \
  --results-dir="$PHASE1B_RESULTS_DIR"
