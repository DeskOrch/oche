# Local Phase 0.5 measurements

These measurements verify the Phase 0.5 AOT artifacts, process harness,
aggregation, and static route-scaling runner. They do not include HTTP load
results and are not sufficient to select Oche's HTTP foundation.

## Environment

- Date: 2026-08-27
- Dart SDK: 3.13.1 stable, Windows x64
- OS: Microsoft Windows NT 10.0.26200.0, 64-bit
- CPU identifier: Intel64 Family 6 Model 79; 28 logical processors visible
- Server mode: Dart native/AOT, one isolate, loopback `127.0.0.1`
- Process trials: five per implementation and endpoint
- Process configuration: concurrency 1 recorded, no warmup, no load generator
- Route scaling: native/AOT, five trials, 20,000 warmup lookups and 200,000
  measured lookups per strategy/route count

The local raw HTTP trial files, aggregate file, and route-scaling JSON are kept
under this directory in the working tree and ignored by Git by default. The
tracked schemas and commands make them reproducible without presenting local
development-host results as a permanent performance promise.

## Native executable size

| Implementation | Bytes | MiB |
| --- | ---: | ---: |
| raw `dart:io` | 6,505,472 | 6.204 |
| Relic | 8,167,424 | 7.789 |
| Oche static | 6,470,656 | 6.171 |

Relic is 1,696,768 bytes larger than the static spike in this build. The static
spike and raw reference differ by only 34,816 bytes; that small difference
should not be treated as an optimization guarantee.

## Startup and idle RSS

Values below are median `[minimum, maximum]` across five new-process trials.
Startup ends only after the selected endpoint returns HTTP 200.

| Implementation | Endpoint | Startup ms | Idle RSS MiB |
| --- | --- | ---: | ---: |
| raw `dart:io` | `/plaintext` | 359.306 `[353.956, 669.158]` | 14.590 `[14.566, 15.039]` |
| raw `dart:io` | `/json` | 356.533 `[349.151, 466.305]` | 14.586 `[14.582, 14.590]` |
| raw `dart:io` | `/users/42` | 352.651 `[345.495, 376.990]` | 14.578 `[14.566, 14.602]` |
| Relic | `/plaintext` | 364.566 `[353.382, 644.865]` | 17.066 `[17.055, 17.074]` |
| Relic | `/json` | 349.556 `[349.075, 356.095]` | 17.070 `[17.059, 17.082]` |
| Relic | `/users/42` | 355.344 `[344.682, 364.820]` | 17.082 `[17.055, 17.082]` |
| Oche static | `/plaintext` | 358.524 `[349.930, 665.263]` | 14.566 `[14.563, 15.063]` |
| Oche static | `/json` | 352.648 `[347.728, 355.815]` | 14.566 `[14.559, 14.594]` |
| Oche static | `/users/42` | 351.329 `[347.698, 358.100]` | 14.570 `[14.555, 14.586]` |

Startup outliers and overlapping ranges leave no meaningful startup ranking.
The static spike's idle RSS tracks raw `dart:io`; Relic uses about 2.5 MiB more
in these process snapshots.

## HTTP load metrics

`oha`, `wrk`, and `wrk2` were unavailable. The following were not measured and
are absent—not zero—in raw and aggregate JSON:

- requests per second;
- p50, p95, and p99 latency;
- peak RSS under sustained load;
- server CPU utilization under sustained load;
- allocation behavior under sustained load.

Install `oha` on this Windows developer environment with:

```powershell
winget install hatoo.oha
```

Then build the AOT binaries and run the documented five-iteration suite.

## Static route lookup scaling

The synthetic lookup stream contains 90% hits and 10% misses. Values are median
lookups/second `[minimum, maximum]` over five AOT trials. They measure lookup
only, not HTTP throughput.

| Routes | Strategy | Lookups/second |
| ---: | --- | ---: |
| 10 | linear scan | 32.05M `[31.62M, 32.66M]` |
| 10 | segmented leaf scan | 32.09M `[26.80M, 35.26M]` |
| 10 | hash map | 56.96M `[56.76M, 57.68M]` |
| 100 | linear scan | 4.11M `[4.07M, 4.15M]` |
| 100 | segmented leaf scan | 10.01M `[9.91M, 10.17M]` |
| 100 | hash map | 49.59M `[48.92M, 50.85M]` |
| 1,000 | linear scan | 0.436M `[0.435M, 0.440M]` |
| 1,000 | segmented leaf scan | 1.440M `[1.434M, 1.446M]` |
| 1,000 | hash map | 41.51M `[41.23M, 43.41M]` |

Median time per 1,000-route lookup was 2,291 ns for linear scan, 695 ns for
segmented leaf scan, and 24.1 ns for the hash table. The result argues against
unbounded linear leaf scans for large static tables. It does not establish a
final router: the grouped synthetic path shape, Dart's `Map` implementation,
parameter routes, method dispatch, collision behavior, and generated-code size
all need broader evaluation.

## Current interpretation

The static spike demonstrates that direct generated-style routing can remain at
the raw baseline's binary-size and idle-memory level. Relic has a visible static
footprint cost but also supplies HTTP behavior that the spike deliberately does
not own. With no external HTTP throughput or latency results, the evidence does
not yet show whether the thin runtime's savings justify its correctness and
maintenance burden. ADR 0002 therefore remains Proposed.
