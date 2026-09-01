#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "The post-Phase-2A validation gate must run on Linux." >&2
  exit 1
fi

case "$(uname -m)" in
  x86_64|amd64) ;;
  *)
    echo "The validation gate requires Linux x86_64; found $(uname -m)." >&2
    exit 1
    ;;
esac

oha_path="${OHA_PATH:-oha}"
results_directory="${RESULTS_DIRECTORY:-benchmarks/results/linux-validation}"
run_id="${RUN_ID:-}"

command -v dart >/dev/null
command -v "$oha_path" >/dev/null

echo "Dart: $(dart --version 2>&1)"
echo "oha: $("$oha_path" --version)"
echo "Kernel: $(uname -srmo)"
if [[ -r /etc/os-release ]]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  echo "Distribution: ${PRETTY_NAME:-unknown}"
fi

dart pub get

pushd examples/hello_oche >/dev/null
dart run build_runner clean
dart run build_runner build
popd >/dev/null

test -f examples/hello_oche/lib/application.oche.dart
mkdir -p build/linux-validation
dart compile exe benchmarks/raw_dart_io/bin/server.dart \
  -o build/linux-validation/raw_dart_io
dart compile exe benchmarks/relic/bin/server.dart \
  -o build/linux-validation/relic
dart run benchmarks/harness/bin/build_public_application.dart \
  build/linux-validation

suite_arguments=(
  "--host=127.0.0.1"
  "--port=8080"
  "--concurrency-sweep=10,100,500"
  "--warmup=5"
  "--duration=30"
  "--iterations=5"
  "--cooldown=2"
  "--oha=$oha_path"
  "--results-dir=$results_directory"
  "--environment-type=Hyper-V VM"
  "--raw-executable=build/linux-validation/raw_dart_io"
  "--relic-executable=build/linux-validation/relic"
  "--public-manifest=build/linux-validation/public-application-build.json"
)
if [[ -n "$run_id" ]]; then
  suite_arguments+=("--run-id=$run_id")
fi

dart run benchmarks/harness/bin/linux_validation_suite.dart \
  "${suite_arguments[@]}"
