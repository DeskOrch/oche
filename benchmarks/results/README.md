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

## Linux status

Linux results were not collected. WSL exposed only a stopped, Docker-internal
`docker-desktop` WSL2 distribution, and the Docker Linux engine was unavailable.
That is not a usable native-Linux validation host. The exact reproducible Linux
script is `tool/run-phase06-linux.sh`; the manual GitHub Actions workflow also
runs the same experiment on Ubuntu and labels its artifacts separately. ADR
0002 therefore remains Proposed.

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
