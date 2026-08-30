#!/usr/bin/env sh
set -eu

PHASE1D_OHA_PATH="${PHASE1D_OHA_PATH:-oha}"
PHASE1D_RESULTS_DIR="${PHASE1D_RESULTS_DIR:-benchmarks/results/phase1d-linux}"
PHASE1D_WORKLOAD_SETS="${PHASE1D_WORKLOAD_SETS:-sync,async,short,error,state}"
PHASE1D_MIDDLEWARE_DEPTHS="${PHASE1D_MIDDLEWARE_DEPTHS:-0,1,3,5,10}"
PHASE1D_IMPLEMENTATIONS="${PHASE1D_IMPLEMENTATIONS:-}"

sh tool/build-middleware-execution.sh
build/middleware_execution/middleware_microbenchmark \
  --calls=5000000 \
  --warmup-calls=500000 \
  --iterations=5 \
  --output="$PHASE1D_RESULTS_DIR/phase1d-middleware-micro-linux-aot.json"

set -- \
  --mode=aot \
  --route-counts=100 \
  --middleware-depths="$PHASE1D_MIDDLEWARE_DEPTHS" \
  --concurrency-sweep="${PHASE1D_CONCURRENCY_SWEEP:-10,100,500}" \
  --warmup="${PHASE1D_WARMUP_SECONDS:-5}" \
  --duration="${PHASE1D_DURATION_SECONDS:-30}" \
  --iterations="${PHASE1D_ITERATIONS:-5}" \
  --cooldown="${PHASE1D_COOLDOWN_SECONDS:-2}" \
  --workload-sets="$PHASE1D_WORKLOAD_SETS" \
  --oha="$PHASE1D_OHA_PATH" \
  --results-dir="$PHASE1D_RESULTS_DIR"
if [ -n "$PHASE1D_IMPLEMENTATIONS" ]; then
  set -- "$@" --implementations="$PHASE1D_IMPLEMENTATIONS"
fi
dart run benchmarks/harness/bin/middleware_execution_suite.dart "$@"
