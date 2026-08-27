#!/usr/bin/env sh
set -eu

PHASE06_OHA_PATH="${PHASE06_OHA_PATH:-oha}"
PHASE06_RESULTS_DIRECTORY="${PHASE06_RESULTS_DIRECTORY:-benchmarks/results/phase06-linux}"

sh tool/build_benchmarks.sh
dart run benchmarks/harness/bin/suite.dart \
  --mode=aot \
  --host=127.0.0.1 \
  --port=8080 \
  --concurrency-sweep=10,100,500 \
  --warmup=5 \
  --duration=30 \
  --iterations=5 \
  --cooldown=2 \
  --load-generator=oha \
  --oha="$PHASE06_OHA_PATH" \
  --results-dir="$PHASE06_RESULTS_DIRECTORY"
