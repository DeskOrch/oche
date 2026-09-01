#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root/examples/hello_oche"
dart run build_runner build

cd "$repo_root"
dart run benchmarks/harness/bin/build_public_application.dart
dart run benchmarks/harness/bin/public_api_suite.dart \
  --concurrency-sweep="${CONCURRENCY_SWEEP:-10,100,500}" \
  --warmup="${WARMUP_SECONDS:-5}" \
  --duration="${DURATION_SECONDS:-30}" \
  --iterations="${ITERATIONS:-5}" \
  --cooldown="${COOLDOWN_SECONDS:-2}" \
  --oha="${OHA_PATH:-oha}" \
  --results-dir="${RESULTS_DIRECTORY:-benchmarks/results/phase2a-linux}"
