# ADR 0006: Response ownership and runtime lifecycle

- Status: Accepted
- Date: 2026-08-31

## Context

ADRs 0003, 0004, and 0005 accept generated segmented routing, specialized typed
handler execution, and the shared closure-free middleware kernel. The remaining
private boundary before a public application API is ownership of
`dart:io HttpResponse`, including commitment, completion, streaming, transport
failure, startup, and shutdown.

The old benchmark server wrote directly and launched `close()` without a
contract that could prevent replacement after commitment or drain accepted
requests during shutdown. Streaming and future protocol upgrade require
controlled transfer without making raw response ownership the normal path.

## Decision

Use one small internal lifecycle controller per accepted request in the Phase
1E runtime while retaining direct specialized response writers.

- Normal handler values leave response ownership with Oche.
- Response state is `uncommitted`, `committed`, or `completed`; ownership is
  independently `framework`, `stream`, or `detachedSocket`.
- Status/header mutation and an empty flush remain uncommitted. The first
  non-empty body add, empty/body close, or socket detach establishes the
  conservative commit boundary.
- Completion is `HttpResponse.done`, not the call to close.
- Before commit, expected/unexpected errors map to fixed 409/500 responses.
  After commit, no replacement is attempted; the first failure is internally
  observable and an owned stream is closed once.
- A second framework completion throws `ResponseLifecycleViolation` and cannot
  replace the first response.
- Streaming receives a narrow internal owner and closes after its entire work,
  including required after-hooks, settles. It writes chunks directly.
- Low-level upgrade explicitly detaches the socket; detached connections are
  no longer part of HTTP request draining.
- Runtime state is created/starting/running/stopping/stopped. Shutdown stops
  acceptance, waits on a counter driven by `response.done`, and force-closes
  connections on timeout. Stop during bind waits for startup; repeated stop
  returns the same future.
- Observability is an optional internal hook interface with no event objects.

No public response, stream, SSE, WebSocket, cancellation, observability,
application, or lifecycle API is selected by this ADR.

## Evidence

Correctness tests cover sync/async/string/bytes/void/structured completion,
header/flush/add/close commitment, middleware short-circuit, expected and
unexpected failure before commit, failure and double completion after commit,
multi-chunk streaming and streaming failure, SSE shape, socket detachment,
best-effort disconnect observation, startup/bind failure, zero-active shutdown,
active sync/async/streaming drain, forced timeout, and repeated stop. All prior
routing, handler, and middleware tests remain intact.

The Windows AOT balanced matrix used 100 routes, middleware depth 3,
concurrency 10/100/500, 5 s warmup, 30 s measurement, five repetitions, and
2 s cooldown. Five groups delivered 99.42–101.45% of Phase 1D; sync/c100
initially measured 95.87% while remaining 98.52% of raw. A focused balanced
ten-repetition repeat measured that group at 101.55% of Phase 1D and 102.25%
of raw. Resolved groups are therefore 99.42–101.55% of Phase 1D and
97.45–102.25% of raw, passing both engineering budgets. Idle RSS changed by
0.01–0.02 MiB; matrix peak RSS changed by -0.15 to +0.71 MiB. The AOT
executable grew 0.35%. A three-chunk streaming diagnostic completed with 100%
success and p99 2.927 ms at concurrency 10.

Detailed semantics, tables, memory qualifications, and reproduction scripts
are in `docs/architecture/response-lifecycle.md` and `tool/run-phase1e-*`.

## Why Accepted

The ownership and lifecycle rules are deterministic across normal,
short-circuit, failure, streaming, upgrade, and shutdown paths. They preserve
the accepted kernels, pass the normal-path performance budgets, expose future
observability without an event model, and leave clear extension points for SSE,
WebSockets, and cooperative cancellation. The remaining risks are bounded and
do not require another private runtime architecture before public API design.

## Consequences

The first public Oche application API may now be designed on top of this
private contract. It should keep normal responses value-based and
framework-owned, make streaming/upgrade explicit advanced paths, preserve
single completion, and surface graceful shutdown without leaking raw lifecycle
state by default.

Native Linux validation, allocation profiling, exact cancellation semantics,
and application policy for detached connections remain future work. ADRs
0003–0005 remain Accepted. ADR 0002 remains Proposed pending independent Linux
validation.
