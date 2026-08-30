#!/usr/bin/env sh
set -eu

PHASE1C_OHA_PATH="${PHASE1C_OHA_PATH:-oha}"
PHASE1C_RESULTS_DIR="${PHASE1C_RESULTS_DIR:-benchmarks/results/phase1c-linux}"
PHASE1C_WORKLOAD_SETS="${PHASE1C_WORKLOAD_SETS:-sync,async,short,error,state}"
PHASE1C_MIDDLEWARE_DEPTHS="${PHASE1C_MIDDLEWARE_DEPTHS:-0,1,3,5,10}"

sh tool/build-middleware-execution.sh
build/middleware_execution/middleware_microbenchmark \
  --calls=5000000 \
  --warmup-calls=500000 \
  --iterations=5 \
  --output="$PHASE1C_RESULTS_DIR/phase1c-middleware-micro-linux-aot.json"
dart run benchmarks/harness/bin/middleware_execution_suite.dart \
  --mode=aot \
  --route-counts=100 \
  --middleware-depths="$PHASE1C_MIDDLEWARE_DEPTHS" \
  --concurrency-sweep="${PHASE1C_CONCURRENCY_SWEEP:-10,100,500}" \
  --warmup="${PHASE1C_WARMUP_SECONDS:-5}" \
  --duration="${PHASE1C_DURATION_SECONDS:-30}" \
  --iterations="${PHASE1C_ITERATIONS:-5}" \
  --cooldown="${PHASE1C_COOLDOWN_SECONDS:-2}" \
  --workload-sets="$PHASE1C_WORKLOAD_SETS" \
  --oha="$PHASE1C_OHA_PATH" \
  --results-dir="$PHASE1C_RESULTS_DIR"
