# Oche HTTP foundation performance laboratory

This laboratory compares equivalent single-isolate HTTP servers built with raw
`dart:io`, Relic, and a narrow Oche static-routing spike over `dart:io`. It does
not select Oche's HTTP foundation. Keep the SDK, machine, power policy, AOT mode,
endpoint, warmup, duration, concurrency, and load-generator version constant.

## HTTP workloads

| Endpoint | Status | Content type | Body |
| --- | ---: | --- | --- |
| `GET /plaintext` | 200 | `text/plain` | `Hello, World!` |
| `GET /json` | 200 | `application/json` | `{"message":"Hello, World!"}` |
| `GET /users/42` | 200 | `application/json` | `{"id":42}` |

All implementations also return the same JSON 400 response for a non-integer
user ID, a plain 404 for an unmatched route, and 405 with `Allow: GET` when a
known path receives the wrong method. They disable compression and request
logging and use one isolate.

The raw implementation is a lower-bound reference. The static spike performs
method dispatch, an exact switch for literal paths, a validated single-segment
prefix check for `/users/{id}`, and a direct handler call. It is deliberately
not a public or general-purpose router.

## Prerequisites

Install stable Dart and run this from the repository root:

```console
dart pub get
```

HTTP load measurements use [`oha`](https://github.com/hatoo/oha) JSON output.
It must be on `PATH`, or its executable path must be passed with `--oha`.

Official installation commands include:

```powershell
winget install hatoo.oha
```

```sh
brew install oha       # macOS
cargo install oha      # platforms with Rust, make, and cmake
```

Without `oha`, use `--load-generator=none`. Startup, idle RSS, and AOT file size
remain measurable, while throughput, latency, load RSS, and load CPU are absent
and listed under `unavailableMetrics`. The harness never substitutes zero.

## Correctness and quality gates

```console
dart format --output=none --set-exit-if-changed .
dart analyze
dart test
```

Contract tests start every implementation on an ephemeral port and validate
status, content type, body, parameter handling, wrong methods, and misses.

## Start servers manually

```console
dart run benchmarks/raw_dart_io/bin/server.dart --host=127.0.0.1 --port=8080
dart run benchmarks/relic/bin/server.dart --host=127.0.0.1 --port=8080
dart run benchmarks/oche_static/bin/server.dart --host=127.0.0.1 --port=8080
```

Press Ctrl+C for graceful shutdown. Each process prints one readiness line and
does not log individual requests.

## Compile native/AOT executables

Windows PowerShell:

```powershell
./tool/build_benchmarks.ps1
```

Linux/macOS:

```sh
sh tool/build_benchmarks.sh
```

Equivalent server commands are:

```console
dart compile exe benchmarks/raw_dart_io/bin/server.dart -o build/raw_dart_io.exe
dart compile exe benchmarks/relic/bin/server.dart -o build/relic.exe
dart compile exe benchmarks/oche_static/bin/server.dart -o build/oche_static.exe
```

Omit `.exe` on Linux/macOS. The scripts also compile the route-scaling runner.

## Run one HTTP benchmark

The harness starts the chosen server, waits for the selected endpoint to return
HTTP 200, measures idle memory, applies warmup, runs `oha`, records load process
samples, writes one raw JSON trial, and stops the server.

```console
dart run benchmarks/harness/bin/benchmark.dart --implementation=oche_static --mode=aot --endpoint=/users/42 --host=127.0.0.1 --port=8080 --duration=30 --concurrency=100 --warmup=5 --output=benchmarks/results/static-users.json
```

`--implementation` accepts `raw_dart_io`, `relic`, or `oche_static`. Defaults
are host `127.0.0.1`, port `8080`, endpoint `/plaintext`, 30-second measurement,
concurrency 100, five-second warmup, JIT mode, and `oha`. Main comparisons should
use AOT. Override the default binary with `--executable=/path/to/binary`.

## Run and aggregate the full suite

The comparison defaults are AOT, five iterations, five-second warmup, 30-second
measurement, concurrency 100, and a two-second cooldown between trials. Every
implementation/endpoint trial remains as an individual JSON file. After the
run, the suite writes an aggregate with sample count, median, minimum, maximum,
and population standard deviation for every available numeric metric.

```console
dart run benchmarks/harness/bin/suite.dart --mode=aot --warmup=5 --duration=30 --concurrency=100 --iterations=5
```

### Balanced deterministic ordering

The suite does not keep implementations or endpoints in a fixed order. For
three values it walks this fixed six-permutation cycle:

```text
1: A, B, C
2: B, C, A
3: C, A, B
4: A, C, B
5: B, A, C
6: C, B, A
```

The cycle then repeats. Every value occupies every position during the default
five iterations and every position exactly twice over six iterations. There is
no random seed: iteration number fully determines the reproducible order. Each
raw result records the full implementation and endpoint orders, their one-based
positions, iteration, global trial sequence, suite run ID, and cooldown.

Cooldown is separate from warmup and measured duration. Configure it with
`--cooldown`; zero disables it.

Output appears under `benchmarks/results/` with one shared timestamp. The final
`*-aggregate.json` references all raw trial paths. To rebuild an aggregate:

```console
dart run benchmarks/harness/bin/aggregate.dart --input-dir=benchmarks/results --prefix=2026-08-27T15-57-20-382047Z
```

Schemas:

- [`harness/schema/benchmark-result.schema.json`](harness/schema/benchmark-result.schema.json)
- [`harness/schema/benchmark-aggregate.schema.json`](harness/schema/benchmark-aggregate.schema.json)

Aggregate groups include median-based normalized ratios against the matching
raw `dart:io` group for requests/second, p99 latency, idle RSS, peak RSS, and
binary size. Raw is 100 for each `percentOfRaw`; `preferredDirection` labels
each metric `higherIsBetter` or `lowerIsBetter`, so p99 or RSS above 100 is
explicitly worse rather than faster.

## Optional concurrency sweep

The normal suite tests one concurrency. To investigate scaling behavior, pass a
comma-separated sweep; every concurrency remains a separate aggregate group:

```console
dart run benchmarks/harness/bin/suite.dart --mode=aot --warmup=5 --duration=30 --iterations=5 --concurrency-sweep=1,10,50,100,250,500
```

This is intentionally optional: the example executes 270 raw HTTP trials.

## Phase 0.6 cross-platform validation

The focused validation uses only concurrency 10, 100, and 500, five iterations,
five-second warmup, 30-second measurement, and two-second cooldown:

```powershell
./tool/run-phase06-windows.ps1 -OhaPath C:\path\to\oha.exe
```

```sh
PHASE06_OHA_PATH=/path/to/oha sh tool/run-phase06-linux.sh
```

Linux environment detection records `native-linux`, `wsl2`, `wsl`,
`linux-container`, or `wsl2-container` from kernel and container evidence. Do
not override WSL2 as native Linux. The optional `--environment-type` override
exists only for hosts whose identity cannot be detected reliably.

The manual GitHub Actions workflow
[`http-foundation-validation.yml`](../.github/workflows/http-foundation-validation.yml)
runs the identical Windows and Ubuntu AOT experiment, pins `oha` 1.16.0, and
uploads every raw and aggregate JSON file as a per-platform artifact.

## Static route-table scaling experiment

This separate microbenchmark measures lookup behavior only. It generates 10,
100, and 1,000 deterministic literal paths as data and uses a fixed 90%-hit,
10%-miss query stream. It does not generate Oche application code or include
HTTP parsing, sockets, response writing, or handler work.

Strategies:

- `linear_scan`: scan every literal route; a simple complexity reference.
- `segmented_leaf_scan`: direct first-segment partition into ten buckets, then
  scan the selected leaf; representative of a shallow generated trie.
- `hash_map`: a prebuilt path-to-handler-index table; representative of
  hash-assisted static dispatch.

Run the AOT experiment with five repeated trials:

```console
./build/route_scaling.exe --route-counts=10,100,1000 --lookups=200000 --warmup-lookups=20000 --iterations=5 --output=benchmarks/results/route-scaling.json
```

Or run it in JIT mode for development only:

```console
dart run benchmarks/harness/bin/route_scaling.dart --route-counts=10,100,1000 --iterations=5
```

The result includes every raw timing/checksum and median/min/max/standard
deviation aggregates. Its schema is
[`harness/schema/route-scaling-result.schema.json`](harness/schema/route-scaling-result.schema.json).
The synthetic grouped path shape favors segment partitioning and must not be
mistaken for a final routing design.

## Phase 1A generated routing kernels

Phase 1A adds two experimental implementations over the same direct `dart:io`
transport:

- `oche_tree`: generated exact segment-count and nested literal/parameter
  branches;
- `oche_indexed`: generated hash switches over literal route skeletons, with
  full equality guards in every case.

They are internal benchmark programs, not public Oche packages or production
code generation. Route counts refer to path templates; method variants on one
path share a template. Generated Dart and all JSON measurements are ignored by
Git.

Build the raw lower bound and all 10/100/1,000-route AOT programs while
recording source size, native size, and approximate compile duration:

```powershell
./tool/build-routing-kernels.ps1
```

```sh
sh tool/build-routing-kernels.sh
```

Each generated executable also runs the deterministic 90%-hit/10%-miss lookup
experiment. For example:

```console
./build/routing_kernel/oche_tree_1000.exe --lookup --source=benchmarks/routing_kernel/generated/tree_1000.dart --output=benchmarks/results/phase1a-lookup-tree-1000.json
```

The complete HTTP suite defaults to AOT, route counts 10/100/1,000,
concurrency 10/100/500, five iterations, five-second warmup, 30-second
measurement, and two-second cooldown. Success and error sets are placed in
separate raw/aggregate result directories. Both implementation order and the
three-workload order use the same balanced deterministic schedule as Phase
0.6.

```powershell
./tool/run-phase1a-windows.ps1 -OhaPath C:\path\to\oha.exe
```

```sh
PHASE1A_OHA_PATH=/path/to/oha sh tool/run-phase1a-linux.sh
```

For a fast harness smoke test without load metrics:

```console
dart run benchmarks/harness/bin/routing_kernel_suite.dart --mode=aot --route-counts=10 --concurrency-sweep=10 --iterations=1 --warmup=0 --duration=1 --cooldown=0 --load-generator=none
```

An interrupted suite can reuse complete, configuration-matching raw trials by
passing the timestamp portion of its existing run as `--suite-run-id`. Every
candidate file is decoded and checked against the expected workload, schedule,
benchmark settings, generated-source size/lines, AOT size, and recorded compile
observation before reuse. SHA-256 fingerprints for the generated source and AOT
executable make different builds unambiguous; malformed or mismatched files are
run again. For example:

```console
dart run benchmarks/harness/bin/routing_kernel_suite.dart --suite-run-id=2026-08-27T23-10-27-951515Z --workload-sets=success
```

The success set contains a literal, one-parameter, and two-parameter request.
The error set contains 405 method mismatch, 400 invalid parameter, and 500
unexpected-handler mapping. Readiness always probes `GET /health`, independently
of the measured method/status. `successRate` is calculated from the expected
status-code distribution, so a correct 405 is a successful error-path trial.

Aggregate groups include request method, expected status, route count, and
workload. `relativeToRaw` compares the matching raw `dart:io` group, while
`relativeToTenRoutes` reports route-table scaling for the same implementation
and workload. Generated source bytes/lines and compile duration are retained
beside the Phase 0.6 runtime metrics.

The recorded native-Windows run completed 405 success trials and 405 error
trials. Its tracked summary, including the exact run IDs and the selected
kernel, is in [`results/README.md`](results/README.md). Raw and aggregate JSON
remain reproducible local artifacts and are intentionally ignored by Git.

The optional middleware invocation experiment is deliberately isolated from
HTTP and from router selection:

```console
./build/routing_kernel/middleware_scaling.exe --calls=5000000 --warmup-calls=500000 --iterations=5 --output=benchmarks/results/phase1a-middleware-windows.json
```

Architecture and URI/security semantics are specified in
[`../docs/architecture/routing-kernel.md`](../docs/architecture/routing-kernel.md).
Phase 1A result schemas are:

- [`harness/schema/routing-kernel-build.schema.json`](harness/schema/routing-kernel-build.schema.json)
- [`harness/schema/routing-kernel-lookup.schema.json`](harness/schema/routing-kernel-lookup.schema.json)
- [`harness/schema/middleware-scaling-result.schema.json`](harness/schema/middleware-scaling-result.schema.json)

## Phase 1B handler execution

Phase 1B keeps the accepted generated segmented tree and changes only its leaf
adapter. Four AOT implementations are measured:

- `handler_raw`: hand-written direct `dart:io` lower bound;
- `handler_phase1a_direct`: generated tree with the Phase 1A-style intermediate
  response contract;
- `handler_specialized`: generated, result-type-specific calls and response
  writes, with no future on synchronous paths;
- `handler_uniform`: direct typed calls normalized through `FutureOr<Object?>`
  and an internal response value.

The three generated candidates have an identical dispatch tree. Parameters are
bound to typed locals before leaf invocation. No candidate uses reflection,
`Function.apply`, runtime route registration, parameter maps, or a service
locator. The package is an internal benchmark package and is not exported by
`package:oche`.

Build all 10/100/1,000-route programs and the microbenchmark:

```powershell
./tool/build-handler-execution.ps1
```

```sh
sh tool/build-handler-execution.sh
```

Run the complete AOT protocol (five-second warmup, 30-second measurement, five
iterations, two-second cooldown, and concurrency 10/100/500):

```powershell
./tool/run-phase1b-windows.ps1 -OhaPath C:\path\to\oha.exe
```

```sh
PHASE1B_OHA_PATH=/path/to/oha sh tool/run-phase1b-linux.sh
```

The default `sync` set contains literal, one-`int`, and two-`int` handlers. The
`async` set contains an immediately completed future, a deterministic event-loop
boundary, and an instance method returning a structured result. The optional
`request` set compares raw `HttpRequest`, a lazy non-copying view, and structured
result mapping:

```console
dart run benchmarks/harness/bin/handler_execution_suite.dart --workload-sets=request
```

Raw JSON, generated sources, and binaries remain ignored. AOT runs can resume
with the same `--suite-run-id`; JIT trials are deliberately rerun because their
result record does not fingerprint imported support source. Aggregates normalize
matching groups both to `handler_raw` and to `handler_phase1a_direct`; the latter
is the primary Phase 1B budget. AOT reuse requires matching source and executable
SHA-256 fingerprints.

Schemas:

- [`harness/schema/handler-execution-build.schema.json`](harness/schema/handler-execution-build.schema.json)
- [`harness/schema/handler-execution-microbenchmark.schema.json`](harness/schema/handler-execution-microbenchmark.schema.json)
- [`harness/schema/benchmark-result.schema.json`](harness/schema/benchmark-result.schema.json)

The contract and current evidence are in
[`../docs/architecture/handler-execution.md`](../docs/architecture/handler-execution.md).

## Phases 1C and 1D middleware execution

Phase 1C compares an unrolled generated direct chain and immutable runtime
traversal. Phase 1D adds the selected shared closure-free kernel. All retain the
accepted tree and specialized handler adapter and cover depths 0/1/3/5/10,
sync/async/mixed continuation, short-circuit, exact unwind, error positions,
lazy/typed state, and static instances. They define no public middleware API.

Build the 38 Phase 1C/1D artifacts plus the focused Phase 1E candidate and
record source/executable hashes, size, lines, and compile observations:

```powershell
./tool/build-middleware-execution.ps1
```

```sh
sh tool/build-middleware-execution.sh
```

Run the full default Windows or Linux protocol (100 routes, depths 0/1/3/5/10,
concurrency 10/100/500, 5-second warmup, 30-second measurement, five balanced
repetitions, and 2-second cooldown):

```powershell
./tool/run-phase1d-windows.ps1 -OhaPath C:\path\to\oha.exe
```

```sh
PHASE1D_OHA_PATH=/path/to/oha sh tool/run-phase1d-linux.sh
```

Workload sets are `sync`, `async`, `short`, `error`, and `state`. A focused
suite may select one or more names with `--workloads`; singleton endpoint order
is valid while implementation order remains balanced. `--implementations` can
select at least two of raw, Phase 1B, generated, runtime, and shared for a
focused comparison. AOT runs with the same
`--suite-run-id` validate build/source fingerprints and reuse only matching
complete trials. Raw JSON, generated source, and native binaries are ignored.

Schemas:

- [`harness/schema/middleware-execution-build.schema.json`](harness/schema/middleware-execution-build.schema.json)
- [`harness/schema/middleware-execution-microbenchmark.schema.json`](harness/schema/middleware-execution-microbenchmark.schema.json)
- [`harness/schema/benchmark-result.schema.json`](harness/schema/benchmark-result.schema.json)

The accepted contract, Windows evidence, and code-growth decision are in
[`../docs/architecture/middleware-execution.md`](../docs/architecture/middleware-execution.md).

## Phase 1E response and runtime lifecycle

Phase 1E keeps the 100-route/depth-3 shared kernel and changes only response
ownership and the server boundary. `response_lifecycle` tracks commitment and
transport completion, provides a narrow stream/detach experiment, and drains
active requests on shutdown. It remains private benchmark code.

Run the limited AOT protocol for normal sync/async responses (raw, Phase 1D,
and Phase 1E at concurrency 10/100/500, five balanced repetitions) followed by
one three-chunk streaming diagnostic:

```powershell
./tool/run-phase1e-windows.ps1 -OhaPath C:\path\to\oha.exe
```

```sh
PHASE1E_OHA_PATH=/path/to/oha sh tool/run-phase1e-linux.sh
```

The `lifecycle` workload set is intentionally focused. Aggregates include
`relativeToPhase1DShared` and `relativeToRaw`; raw trials and the focused build
manifest remain ignored. Commitment, disconnect, shutdown, memory, and Windows
AOT findings are in
[`../docs/architecture/response-lifecycle.md`](../docs/architecture/response-lifecycle.md).

## Phase 2A public application

Phase 2A benchmarks the generated `examples/hello_oche` application itself,
not a private router surrogate. The suite builds its native executable, records
generated source lines/bytes, compile duration and binary size, then measures
sync and async typed routes at concurrency 10/100/500. Raw JSON, manifests, and
native binaries remain ignored by Git.

Run the default AOT protocol (five-second warmup, 30-second measurement, five
repetitions, and two-second cooldown):

```powershell
./tool/run-phase2a-windows.ps1 -OhaPath C:\path\to\oha.exe
```

```sh
OHA_PATH=/path/to/oha sh tool/run-phase2a-linux.sh
```

If a group falls below a retention target, compare the public, Phase 1E, and
raw binaries in one balanced run. The focused harness defaults to ten
interleaved repetitions for sync concurrency 100/500 and async concurrency
500:

```console
dart run benchmarks/harness/bin/public_api_focused_comparison.dart --oha=C:\path\to\oha.exe
```

The accepted Windows evidence, including the focused repeat, is in
[`../docs/architecture/code-generation.md`](../docs/architecture/code-generation.md).

## Post-Phase-2A Linux validation gate

The Linux gate compares raw `dart:io`, Relic, and the production-generated
public Oche application. All three expose identical validation paths and
response shapes for a synchronous handler, an asynchronous handler, and an
`int`-bound parameterized handler. Oche is generated from annotations with the
production builder; `oche_static` and the internal kernel spikes are excluded.

On the Ubuntu x86_64 Hyper-V validation VM, run from the repository root:

```sh
./tool/run-linux-validation.sh
```

The entry point verifies Linux x86_64, resolves dependencies, regenerates the
public application from a clean build graph, compiles all three servers to AOT,
and runs the fixed 10/100/500 concurrency matrix with 5-second warmup,
30-second measurement, five balanced repetitions, and 2-second cooldown.
`OHA_PATH`, `RESULTS_DIRECTORY`, and `RUN_ID` may select the executable and
output location without changing the protocol.

Raw trials and the aggregate are written below
`benchmarks/results/linux-validation/<run-id>/` and remain ignored by Git. The
aggregate retains every raw filename and normalizes throughput, latency,
startup, RSS, CPU, and binary size against raw `dart:io`. Each trial records
the distribution, kernel, architecture, CPU, logical CPU count, total RAM,
Dart and `oha` versions, and `environmentType: Hyper-V VM` where available.
The reviewed evidence and acceptance caveats are recorded in
[ADR 0002](../docs/adr/0002-http-foundation.md).

## Measurement methodology

- **Requests/second and latency:** `oha --no-tui --output-format json`; p50,
  p95, and p99 are retained in milliseconds.
- **Startup:** monotonic time immediately before `Process.start` through the
  first HTTP 200 from the selected endpoint. Warmup occurs afterward.
- **Idle RSS:** Windows `Get-Process.WorkingSet64`, or RSS reported by `ps` on
  Linux/macOS, sampled after readiness and before warmup.
- **Load RSS:** maximum server RSS observed at 250 ms intervals during `oha`.
- **CPU:** server CPU-time delta divided by load wall time. One fully busy
  logical CPU is 100%; runtime helper threads can put the whole process above
  100% even when application dispatch uses one isolate.
- **Executable size:** native file length in MiB; absent for JIT runs.
- **Environment metadata:** OS/version, ABI architecture, Dart version, CPU
  model when available, logical CPUs, environment type, and load-generator
  version are captured before server startup timing begins.

## Profiling

The current AOT workflow deliberately avoids attaching the Dart VM service,
which would change execution mode and startup characteristics. No reliable
allocation profile was collected on the Windows host. If HTTP load evidence
shows a material difference, use platform-native sampling with AOT debugging
information or a separate profile-mode/JIT diagnostic run, label it clearly,
and do not combine those timings with the AOT comparison.

## Reproducibility and limitations

Use an otherwise idle representative machine, a fixed power profile, the same
`oha` binary, and at least five trials. Preserve raw JSON and report medians.
Prefer a Linux production-like host and, for serious saturation testing, a
separate load-generator host. Antivirus, thermal scaling, loopback contention,
background work, and OS caches affect local results.

"Cold startup" here means a new process whose socket has not yet been bound; it
does not flush OS file caches. RSS sampling can miss short peaks. Windows lacks
a portable graceful child-signal mechanism in this harness, so automated runs
terminate the child after capture; manual Ctrl+C exercises graceful shutdown.
Unavailable host process metrics remain absent.
