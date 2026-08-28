# ADR 0003: Generated routing kernel

- Status: Accepted
- Date: 2026-08-28

## Context

Oche intends to generate route dispatch ahead of runtime over a thin `dart:io`
transport. Phase 0.5 rejected unbounded linear and leaf scanning at larger route
counts, but did not establish a mixed literal/parameter architecture. Phase 1A
therefore compares a generated segmented tree with a generated hash-assisted
index at 10, 100, and 1,000 path templates.

This decision concerns internal emitted code only. It does not authorize a
public application API, production code-generation package, middleware API, or
any Phase 1B feature. ADR 0002 remains Proposed pending independent Linux HTTP
foundation evidence.

## Decision drivers

- identical deterministic literal-over-parameter semantics;
- direct typed parameter binding without a parameter map;
- correct path-aware 404/405 behavior and stable `Allow`;
- predictable handler-error mapping without information disclosure;
- at least 95% of the matching raw `dart:io` HTTP throughput on representative
  successful routes;
- stable p99, RSS, CPU efficiency, and startup;
- route-count scaling in isolated and complete HTTP measurements;
- generated source, AOT size, compile-time growth, and maintainability.

## Options

### Generated segmented tree

Switch on exact segment count, follow literal branches before parameter leaves,
parse typed values in local variables, and call handlers directly. This is the
most transparent representation and has the smallest generator correctness
surface, at the cost of more source lines in wide route sets.

### Generated hash-assisted index

Switch on hashes of route-defining literal positions, verify every literal in
the selected case, bind parameters locally, and call handlers directly. This
can reduce branch depth but adds runtime hashing and generator/collision
complexity; the final formatted benchmark source was larger than tree source.
Equality guards prevent hash collision misrouting.

The required generated sets contain no declared-route hash collision. Equality
guards also prevent an unknown colliding input from matching. A future
production generator would need to bucket multiple declared routes with the
same hash rather than assume collisions remain absent.

## Evidence

Both candidates pass the same generated-server HTTP contract, including
literal precedence, one and multiple typed parameters, all five required
methods, strict slash behavior, query separation, synthetic route shapes,
400/404/405, stable `Allow`, and generic expected/unexpected error responses.

On the final formatter-safe Windows AOT build, 10-to-1,000-route executable
growth was 412,672 bytes for tree and 465,920 bytes for indexed. At 1,000
routes, indexed source was 455,022 bytes/10,708 lines versus tree's 417,693
bytes/10,028 lines. The indexed executable was 53,760 bytes larger and its one
compilation observation was about 1.72 seconds longer. These compile times are
diagnostic observations, not precise performance claims.

The full balanced HTTP and isolated lookup evidence is recorded and interpreted
in `docs/architecture/routing-kernel.md`. The native-Windows AOT suite completed
405 successful-route trials and 405 error-route trials. Every error group
returned its expected 400, 405, or 500 status.

Across 27 successful HTTP groups, tree throughput averaged 100.11% of matching
raw `dart:io` and its minimum group was 96.59%. Indexed averaged 100.37%, but
one 1,000-route literal group measured 94.69%, with p99 at 117.47% of raw.
Neither candidate established a material HTTP, RSS, CPU, or startup advantage.

The isolated distributed lookup stream exposed the opposite scaling trade-off:
tree moved from 270.79 ns at 10 routes to 1,697.07 ns at 1,000, while indexed
moved from 318.08 ns to 820.79 ns. Indexed was 2.07 times faster at 1,000
routes, but the absolute tree cost did not produce a material regression in
the complete HTTP results.

## Decision

Adopt generated segmented-tree dispatch as Oche's internal routing-kernel
direction. Its direct control flow, all-groups HTTP budget compliance, smaller
1,000-route binary, faster observed large build, and simpler collision-free
generator outweigh the indexed candidate's isolated large-table advantage.

Confidence is medium-high for the tested Windows route shapes. The decision
must be revisited if a future representative full-table HTTP workload shows
the tree lookup growth becoming material, or if applications substantially
exceed 1,000 generated route templates.

## Consequences

- Literal segments always outrank parameter segments; full-path matching is
  mandatory and wildcards remain out of scope.
- Parameters are generated locals and direct handler arguments.
- Runtime route registration, reflection, regex-by-default, dynamic handler
  invocation, and generic router maps remain excluded from the hot path.
- Strict URI behavior and internal error mapping are part of the kernel
  contract and must remain covered by end-to-end tests.
- Generated benchmark sources and raw JSON evidence stay ignored by Git;
  tracked reports summarize reproducible measurements.
- The smallest follow-up after a decision is an internal handler-adapter spike
  over the chosen dispatcher, not a public framework surface.
