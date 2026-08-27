$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

New-Item -ItemType Directory -Force -Path 'build' | Out-Null
dart compile exe benchmarks/raw_dart_io/bin/server.dart -o build/raw_dart_io.exe
dart compile exe benchmarks/relic/bin/server.dart -o build/relic.exe
dart compile exe benchmarks/oche_static/bin/server.dart -o build/oche_static.exe
dart compile exe benchmarks/harness/bin/route_scaling.dart -o build/route_scaling.exe

Get-Item build/raw_dart_io.exe, build/relic.exe, build/oche_static.exe, build/route_scaling.exe |
    Select-Object Name, Length, LastWriteTime
