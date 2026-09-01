# Local benchmark measurements

These are development-host measurements, not production performance promises.
When available locally or as workflow artifacts, generated JSON is the
authoritative evidence. The tracked tables summarize medians and clearly
identify where values are averaged across endpoints.

## Phase 0.6 balanced Windows AOT validation

Local evidence set (generated JSON is intentionally ignored by Git):

- `phase06-windows-balanced/2026-08-27T20-34-49-497561Z-aggregate.json`
- `phase06-windows-balanced/`: 135 raw trial files, five per each of 27
  implementation/endpoint/concurrency groups

### Environment and method

- Date: 2026-08-27
- Environment type: `native-windows`
- OS: Windows 11 Pro 10.0 build 26200, Windows x64
- CPU: Intel Xeon E5-2680 v4 at 2.40 GHz, 28 logical CPUs visible
- Dart: 3.13.1 stable, AOT native executables, one isolate
- Load generator: `oha` 1.16.0 on loopback `127.0.0.1`
- Endpoints: `/plaintext`, `/json`, `/users/42`
- Concurrency: 10, 100, 500
- Per trial: five seconds warmup, 30 seconds measured, two seconds cooldown
- Repetitions: five per group

Implementation and endpoint order follow the same deterministic six-permutation
cycle. The five-iteration run puts each item first, middle, and last at least
once. Raw results record both full orders and positions, iteration, sequence,
suite run ID, cooldown, and system metadata.

### Absolute results

The table uses the mean of the three endpoint medians at each concurrency. The
aggregate keeps each endpoint separate and includes sample count, median,
minimum, maximum, and population standard deviation.

| Concurrency | Implementation | Requests/s | p50 ms | p95 ms | p99 ms | Idle RSS MiB | Peak RSS MiB | Server CPU |
| ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 10 | raw `dart:io` | 5,865.6 | 1.664 | 1.951 | 2.194 | 14.581 | 18.622 | 124.6% |
| 10 | Oche static | 5,900.4 | 1.661 | 1.945 | 2.205 | 14.572 | 18.479 | 124.8% |
| 10 | Relic | 4,756.5 | 2.028 | 2.720 | 3.097 | 17.065 | 53.092 | 125.6% |
| 100 | raw `dart:io` | 5,846.3 | 16.852 | 18.736 | 20.398 | 14.583 | 55.391 | 121.8% |
| 100 | Oche static | 5,866.9 | 16.740 | 18.586 | 20.506 | 14.572 | 55.065 | 122.5% |
| 100 | Relic | 4,919.6 | 20.131 | 22.817 | 24.776 | 17.074 | 90.436 | 124.9% |
| 500 | raw `dart:io` | 6,244.3 | 82.863 | 93.858 | 99.520 | 14.581 | 84.757 | 124.9% |
| 500 | Oche static | 6,273.2 | 82.482 | 93.108 | 97.053 | 14.569 | 84.254 | 124.0% |
| 500 | Relic | 4,515.9 | 110.696 | 117.608 | 123.998 | 17.070 | 122.948 | 126.4% |

`Server CPU` is whole-process CPU-time delta divided by wall time. One fully
busy logical CPU is 100%; runtime helper threads can make a single-isolate
server process exceed 100%.

### Relative to raw `dart:io`

Each range spans the three endpoint-level median ratios. Higher throughput is
better; lower p99 and RSS are better.

| Concurrency | Implementation | Requests/s | p99 | Idle RSS | Peak RSS |
| ---: | --- | ---: | ---: | ---: | ---: |
| 10 | Oche static | 99.53-101.77% | 94.37-106.15% | 99.89-100.00% | 97.57-100.23% |
| 10 | Relic | 79.12-82.26% | 135.99-150.37% | 117.01-117.07% | 281.34-290.47% |
| 100 | Oche static | 99.34-102.13% | 96.95-105.04% | 99.87-100.00% | 99.07-99.82% |
| 100 | Relic | 83.14-85.91% | 108.72-130.73% | 117.01-117.15% | 162.96-163.48% |
| 500 | Oche static | 100.26-100.59% | 95.47-98.73% | 99.87-99.95% | 98.15-100.75% |
| 500 | Relic | 71.76-72.79% | 123.39-126.86% | 117.01-117.15% | 143.49-145.97% |

Native executable size was 6.204 MiB for raw `dart:io`, 6.171 MiB for Oche
static, and 7.789 MiB for Relic. Relative to raw, where lower is better, that is
100.00%, 99.46%, and 125.55%. Startup medians overlapped at about 308-327 ms and
do not establish a ranking.

### Interpretation and irregularities

Balancing reproduced the prior fixed-order result. Oche static still meets the
95%-of-raw criterion for every endpoint and concurrency. Relic remains
14.09-20.88% behind raw at concurrency 10/100 and 27.21-28.24% behind at 500,
with materially higher p99, idle RSS, peak RSS, and binary size.

Twenty of the 45 concurrency-500 trials reported tiny non-success fractions.
The worst was approximately 20 of 182,865 requests, or 99.989% success. Relic
`/users/42` at concurrency 100 also had one p99 outlier of 101.689 ms; the other
four trials were 24.031-32.642 ms, leaving the group median at 24.379 ms. The
generated aggregate retains both events.

The data comes from one loopback developer host, where server and load generator
contend for the same machine. It supports the relative Windows ranking but not a
universal absolute throughput claim.

## Phase 0.6 Linux status

Linux results were not collected during Phase 0.6. WSL exposed only a stopped,
Docker-internal `docker-desktop` WSL2 distribution, and the Docker Linux engine
was unavailable. That is not a usable native-Linux validation host. The exact
reproducible Linux script is `tool/run-phase06-linux.sh`; the manual GitHub
Actions workflow also runs the same experiment on Ubuntu and labels its
artifacts separately. The later post-Phase-2A public-application gate produced
local Ubuntu evidence in `oche-linux-validation.zip` at the repository root;
[ADR 0002](../../docs/adr/0002-http-foundation.md) records its review and is
now Accepted.

## Retained Phase 0.5 route-scaling result

The Phase 0.5 AOT lookup experiment remains in
`phase05-route-scaling-windows-aot.json`. It used a 90%-hit, 10%-miss stream and
measures lookup only, not HTTP throughput.

| Routes | Linear scan | Segmented leaf scan | Hash map |
| ---: | ---: | ---: | ---: |
| 10 | 32.05M/s | 32.09M/s | 56.96M/s |
| 100 | 4.11M/s | 10.01M/s | 49.59M/s |
| 1,000 | 0.436M/s | 1.440M/s | 41.51M/s |

This rejects unbounded leaf scanning for large route tables in that synthetic
shape. It does not select the final routing data structure; mixed literal and
parameterized generated routing remains a later architectural experiment.

## Phase 1A generated routing-kernel results

### Environment and protocol

- Dates: 2026-08-27 through 2026-08-28
- Environment: the same native-Windows host and Dart 3.13.1 AOT setup above
- Implementations: hand-written raw `dart:io`, generated segmented tree, and
  generated guarded hash-assisted index
- Route templates: 10, 100, and 1,000
- Success workloads: literal, one typed parameter, and two typed parameters
- Error workloads: 405 method mismatch, 400 invalid parameter, and 500
  unexpected exception
- Concurrency: 10, 100, and 500; five repetitions per group
- Per trial: five-second warmup, 30-second measurement, two-second cooldown
- Run IDs: `2026-08-27T23-10-27-951515Z` (success) and
  `2026-08-28T15-00-00-000000Z` (error)

The two matrices contain 405 raw trials each. All JSON measurements remain
local and ignored by Git; this tracked report preserves their summary.

### Successful HTTP requests

Values average the three workload-level medians for each point. Percentages in
parentheses are throughput relative to the matching raw group.

| Routes | Concurrency | Raw req/s | Tree req/s | Indexed req/s | Raw p99 ms | Tree p99 ms | Indexed p99 ms |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 10 | 10 | 5,635.4 | 5,718.1 (101.48%) | 5,766.8 (102.36%) | 2.464 | 2.366 | 2.292 |
| 10 | 100 | 5,858.7 | 5,855.6 (99.95%) | 5,860.6 (100.03%) | 19.840 | 19.652 | 19.219 |
| 10 | 500 | 6,158.8 | 6,191.4 (100.53%) | 6,203.1 (100.72%) | 101.325 | 99.490 | 98.179 |
| 100 | 10 | 5,874.7 | 5,932.1 (100.99%) | 5,893.4 (100.33%) | 2.185 | 2.116 | 2.195 |
| 100 | 100 | 5,951.5 | 5,941.7 (99.84%) | 5,966.8 (100.26%) | 18.828 | 18.950 | 18.879 |
| 100 | 500 | 5,878.6 | 5,982.0 (101.76%) | 5,945.5 (101.13%) | 112.090 | 109.862 | 110.205 |
| 1,000 | 10 | 5,604.7 | 5,486.8 (97.94%) | 5,552.3 (99.11%) | 2.519 | 2.683 | 2.618 |
| 1,000 | 100 | 5,803.3 | 5,709.7 (98.39%) | 5,788.2 (99.74%) | 21.299 | 22.813 | 21.240 |
| 1,000 | 500 | 6,041.6 | 6,047.8 (100.10%) | 6,018.1 (99.61%) | 105.007 | 105.681 | 109.079 |

Tree met the 95%-of-raw budget in all 27 workload groups; its minimum was
96.59%. Indexed averaged slightly higher overall but had one noisy
1,000-route/literal/c=10 group at 94.69% of raw and p99 at 117.47% of raw.
At concurrency 100, p50/p95/p99 stayed close: across 10/100/1,000 routes tree
ranged 16.621-17.103/17.775-19.566/18.950-22.813 ms and indexed ranged
16.578-16.934/17.662-18.783/18.879-21.240 ms.

Idle RSS was 14.637-15.020 MiB for tree and 14.645-15.066 MiB for indexed;
peak RSS was 18.895-86.863 MiB and 18.887-87.316 MiB. CPU ranges were
117.40-126.28% and 117.88-126.54%, while startup ranges were 300.47-323.44 ms
and 300.45-330.30 ms. These overlap with raw and do not establish a candidate
ranking.

All 405 error trials returned their expected status, giving every aggregate
group a 1.0 success rate. Error-path throughput remained effectively tied with
raw.

### Isolated lookup and growth

The AOT lookup stream used 90% hits, 10% misses, five million lookups per
iteration, and five iterations.

| Candidate | Routes | Lookups/s | ns/lookup | Source bytes | AOT bytes | Compile ms |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Tree | 10 | 3,692,965 | 270.79 | 3,804 | 6,577,664 | 2,776 |
| Tree | 100 | 1,653,117 | 604.92 | 41,502 | 6,630,400 | 2,898 |
| Tree | 1,000 | 589,251 | 1,697.07 | 417,693 | 6,990,336 | 4,524 |
| Indexed | 10 | 3,143,852 | 318.08 | 5,006 | 6,578,176 | 2,771 |
| Indexed | 100 | 1,608,910 | 621.54 | 45,716 | 6,631,424 | 2,944 |
| Indexed | 1,000 | 1,218,332 | 820.79 | 455,022 | 7,044,096 | 6,248 |

Indexed is 2.07 times faster in the distributed 1,000-route lookup, while tree
is faster at 10 and 100. Tree's 1.70 microsecond large-table lookup is the main
pathological case, but it did not materially affect the complete HTTP matrix.
At 1,000 routes, tree has the smaller binary, faster observed compile, and fewer
source bytes and lines after deterministic formatting.

### Decision

ADR 0003 accepts the segmented tree. It is simpler, met the HTTP budget in
every group, and has better large-build characteristics. Confidence is
medium-high for these Windows shapes. The indexed candidate remains useful
evidence and should be reconsidered if representative full-table HTTP traffic
or route counts beyond 1,000 make tree lookup time material.

## Phase 1B handler-execution results

### Method

The native-Windows AOT screening matrix used the accepted generated segmented
tree at 10/100/1,000 routes, concurrency 10/100/500, three synchronous
workloads, four implementations, and five balanced repetitions (540 trials).
For practical local runtime it used one-second warmup, five-second measurement,
and no cooldown. The checked-in scripts default to the target 5/30/5/2-second
protocol. Focused async and request-view matrices used the same abbreviated
protocol at 100 routes and concurrency 100.

The marginal synchronous group was rerun independently with the full target
protocol: five-second warmup, 30-second measurement, five repetitions, and
two-second cooldown. JSON results and build manifests remain ignored by Git.

### Throughput and latency

Across all 27 synchronous groups, specialized averaged 100.79% of the matching
Phase 1A direct group and 100.41% of raw. Uniform averaged 101.06% and 100.67%.
The abbreviated specialized ranges were 97.30-110.52% of Phase 1A direct and
96.36-107.90% of raw. No specialized group missed the 95%-of-raw long-term
budget.

The full-protocol diagnostic for the one-`int` handler at 100 routes and
concurrency 500 was:

| Implementation | Requests/s | p50 ms | p95 ms | p99 ms | Peak RSS MiB | Server CPU |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Raw `dart:io` | 5,972.45 | 85.820 | 99.620 | 107.323 | 84.008 | 121.02% |
| Phase 1A direct | 6,064.25 | 84.341 | 98.552 | 107.375 | 84.137 | 120.17% |
| Specialized | 6,007.96 | 84.516 | 100.727 | 112.200 | 83.359 | 119.20% |
| Uniform | 6,205.16 | 82.893 | 94.616 | 100.303 | 85.145 | 121.33% |

Specialized is 99.07% of Phase 1A direct and 100.59% of raw in this longer
measurement. Five-trial ranges overlap, so p99 and the apparent uniform lead
are not treated as architectural differences.

At 100 routes and concurrency 100, specialized was 100.79% of Phase 1A direct
for the immediately completed future, 100.63% for a real event-loop boundary,
102.57% for a statically known instance method, 100.06% for raw-request access,
98.84% for the lazy request view, and 99.57% for structured mapping. Within the
specialized candidate, the request view reached 99.07% of raw-request
throughput; results across all candidates did not establish a consistent HTTP
difference.

### Resources and growth

Specialized synchronous groups used 14.512-14.840 MiB idle RSS,
18.758-84.000 MiB peak RSS, and 109.21-120.10% server CPU. Uniform ranges were
14.523-14.832 MiB, 18.676-85.672 MiB, and 109.54-121.30%. They overlap the raw
and Phase 1A direct ranges.

At 10/100/1,000 routes, specialized AOT executables were
6.208/6.226/6.529 MiB. Uniform executables were byte-identical; Phase 1A direct
was 512 bytes larger at each size. Specialized generated
5,854/35,187/324,978 source bytes, compared with
6,664/36,048/325,839 for uniform. Raw `dart:io` was 6.207 MiB.

ADR 0004 accepts specialized generated leaf adapters. Detailed allocation
observations, microbenchmark medians, caveats, and the execution contract are
in `docs/architecture/handler-execution.md`.

## Phase 1C middleware-execution results

### Method and outcome

The primary native-Windows AOT matrix used the representative one-`int` route,
100 generated routes, depths 1 and 3, concurrency 10/100/500, five-second
warmup, 30-second measurement, five balanced repetitions, and two-second
cooldown (120 trials). JSON evidence is ignored by Git; the local run ID is
`primary-30s`.

Generated direct-chain medians were:

| Depth | Concurrency | Requests/s | vs Phase 1B | vs raw | p50 ms | p95 ms | p99 ms | Peak RSS MiB | CPU |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 10 | 5,424.44 | 96.22% | 100.02% | 1.759 | 2.270 | 2.661 | 18.93 | 121.19% |
| 1 | 100 | 5,688.55 | 98.48% | 98.62% | 17.187 | 19.385 | 21.771 | 55.49 | 117.40% |
| 1 | 500 | 5,744.48 | 99.05% | 102.25% | 88.761 | 104.907 | 120.477 | 85.20 | 122.44% |
| 3 | 10 | 5,420.86 | 97.56% | 98.91% | 1.783 | 2.300 | 2.782 | 18.98 | 121.04% |
| 3 | 100 | 4,908.47 | 99.11% | 96.71% | 19.204 | 25.133 | 27.811 | 55.66 | 116.98% |
| 3 | 500 | 5,754.63 | 99.71% | 99.35% | 88.545 | 104.746 | 115.335 | 83.73 | 122.46% |

Depth three passed its 97% incremental target everywhere. Depth one passed its
98% target at concurrency 100 and 500, but missed at concurrency 10 despite
matching raw. All complete generated groups remained above 95% of raw. Runtime
traversal was tied in HTTP throughput.

A separate 300-trial diagnostic depth curve used one-second warmup and three
measured seconds for depths 0/1/3/5/10. The median generated requests/s across
the three concurrency medians was 5,365.7/5,402.4/5,374.9/5,622.9/5,444.9.
Another 102 abbreviated trials covered async/mixed, short-circuit, errors,
order, state, and instance behavior with every expected status observed.

At 1,000 routes/depth 3, generated direct composition used 1,694.4 KiB source,
7.562 MiB AOT, and 6.73 seconds observed compile; runtime traversal used 769.5
KiB, 7.472 MiB, and 5.51 seconds. At 100 routes/depth 10 the corresponding
source/AOT sizes were 716.3 KiB/6.623 MiB and 78.1 KiB/6.335 MiB.

ADR 0005 therefore remains Proposed, with generated direct composition only the
provisional lead. Detailed semantics, microbenchmark results, build tables, and
limitations are in `docs/architecture/middleware-execution.md`.

## Phase 1D shared-kernel results

Phase 1D adds Candidate C, a shared closure-free entry/exit kernel around the
direct typed handler call. Raw JSON remains local and ignored by Git.

The ten-repetition d1/c10 repeat measured C at 5,492.26 req/s, 102.05% of Phase
1B and 100.29% of raw. The prior 96.22% generated result did not reproduce.
Across the five-repetition production matrix, C d3 was 99.58-100.22% of Phase
1B. A contemporaneous raw/C comparison put d3 at 99.81%, 102.89%, and 101.75%
of raw for concurrency 10/100/500. d1/c100 retained one incremental miss at
95.24% of Phase 1B, but remained 98.90% of raw in the focused ten-trial repeat.

At 1,000 routes/d3, C used 829,694 source bytes, 27,744 lines, a 7,505,408-byte
AOT executable, and 5.170 seconds observed compile. Generated A used
1,764,694/54,795/7,929,344/6.822; runtime B used
817,702/28,747/7,834,624/5.450. C also delivered 5,453.54 req/s, 101.82% of
Phase 1B and 102.97% of raw in the representative HTTP comparison.

ADR 0005 is Accepted with Candidate C. Full protocol, latency/RSS/CPU tables,
microbenchmarks, maintainability analysis, and caveats are in
`docs/architecture/middleware-execution.md`.

## Phase 1E response-lifecycle results

The native-Windows run `2026-08-31-final-contract-lifecycle` measured the
focused 100-route/depth-3 response candidate against raw `dart:io` and the
accepted Phase 1D shared kernel. It used `oha` 1.16.0, concurrency 10/100/500,
5-second warmup, 30-second measurement, five balanced repetitions, and
2-second cooldown (90 successful raw trials).

Phase 1E normal sync throughput was 5,319.46/5,390.84/5,770.51 req/s at
c10/c100/c500: 99.45%/95.87%/101.45% of Phase 1D and
97.45%/98.52%/100.59% of raw. Normal async throughput was
5,418.61/5,442.58/5,685.02 req/s: 100.67%/101.32%/99.42% of Phase 1D and
98.86%/99.03%/99.94% of raw.

Because sync/c100 was the sole incremental miss and Phase 1D itself reached
102.77% of raw, a focused ten-repetition repeat measured Phase 1E at 5,467.36
req/s: 101.55% of Phase 1D and 102.25% of raw. The resolved evidence passes the
98% incremental and 95% complete-stack budgets while retaining the initial
miss as benchmark-variance evidence.

Idle RSS was 14.67–14.69 MiB, 0.01–0.02 MiB above Phase 1D. Matrix peak RSS
ranged from 0.15 MiB below to 0.71 MiB above Phase 1D. The focused
AOT executable was 6,618,624 bytes, 0.35% above Phase 1D. A separate
three-chunk streaming run at c10 produced 100% success, 5,260.09 req/s,
p99 2.927 ms, and 14.67/18.95 MiB idle/peak RSS; it is a correctness/overhead
diagnostic, not a raw-throughput comparison.

Raw JSON remains ignored. The full contract and qualifications are in
[`../../docs/architecture/response-lifecycle.md`](../../docs/architecture/response-lifecycle.md).
