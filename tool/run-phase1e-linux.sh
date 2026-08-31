#!/usr/bin/env sh
set -eu

PHASE1E_OHA_PATH="${PHASE1E_OHA_PATH:-oha}"
PHASE1E_RESULTS_DIR="${PHASE1E_RESULTS_DIR:-benchmarks/results/phase1e-linux}"

sh tool/build-middleware-execution.sh

dart run benchmarks/harness/bin/middleware_execution_suite.dart \
  --mode=aot \
  --route-counts=100 \
  --middleware-depths=3 \
  --concurrency-sweep="${PHASE1E_CONCURRENCY_SWEEP:-10,100,500}" \
  --warmup="${PHASE1E_WARMUP_SECONDS:-5}" \
  --duration="${PHASE1E_DURATION_SECONDS:-30}" \
  --iterations="${PHASE1E_ITERATIONS:-5}" \
  --cooldown="${PHASE1E_COOLDOWN_SECONDS:-2}" \
  --workload-sets=lifecycle \
  --oha="$PHASE1E_OHA_PATH" \
  --results-dir="$PHASE1E_RESULTS_DIR"

dart run benchmarks/harness/bin/benchmark.dart \
  --implementation=response_lifecycle \
  --mode=aot \
  --endpoint=/stream \
  --readiness-endpoint=/health \
  --expected-status=200 \
  --route-count=100 \
  --middleware-depth=3 \
  --middleware-profile=streaming \
  --workload=streaming_three_chunk \
  --concurrency=10 \
  --warmup="${PHASE1E_WARMUP_SECONDS:-5}" \
  --duration="${PHASE1E_DURATION_SECONDS:-30}" \
  --oha="$PHASE1E_OHA_PATH" \
  --executable=build/middleware_execution/response_lifecycle_r100_d3 \
  --generated-source=benchmarks/handler_execution/generated_middleware/lifecycle_r100_d3.dart \
  --output="$PHASE1E_RESULTS_DIR/phase1e-streaming-linux-aot.json"
