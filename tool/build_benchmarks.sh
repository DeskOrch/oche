#!/usr/bin/env sh
set -eu

mkdir -p build
dart compile exe benchmarks/raw_dart_io/bin/server.dart -o build/raw_dart_io
dart compile exe benchmarks/relic/bin/server.dart -o build/relic
dart compile exe benchmarks/oche_static/bin/server.dart -o build/oche_static
dart compile exe benchmarks/harness/bin/route_scaling.dart -o build/route_scaling
ls -lh build/raw_dart_io build/relic build/oche_static build/route_scaling
