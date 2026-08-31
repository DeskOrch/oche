# Internal response ownership and runtime lifecycle

## Scope

Phase 1E defines the last private runtime boundary before a public Oche API. It
does not define `Oche`, application registration, a public request/response
type, streaming/SSE/WebSocket APIs, cancellation, logging, or deployment
management. The experiment remains under `benchmarks/handler_execution`.

The Phase 1E benchmark candidate retains the accepted Phase 1D generated route
tree, typed binding, and shared closure-free middleware kernel. Generation
substitutes only terminal response operations and the server boundary. The
Phase 1D executable remains a separate baseline.

## Ownership contract

A normal handler returns a typed value. The framework owns `HttpResponse`,
applies status and headers, serializes directly into bytes, writes once, and
starts close once. User code neither receives an owning response wrapper nor
closes the response. The Phase 1B mappings remain specialized for text, JSON
strings, bytes, `void`/204, and the experiment's structured `UserResult`, in
both synchronous and asynchronous paths.

Every accepted request has one small `InternalResponseLifecycle` controller.
It stores response state, ownership, close/completion-attempt flags, the first
post-commit failure, and an optional hook reference. It is associated with the
underlying response through an `Expando` and removed after transport
completion. Normal results are still written directly; there is no generic
intermediate response object, argument collection, or body buffer beyond the
result's required encoding.

Ownership is separate from response state:

- `framework`: only specialized terminal writers may complete the response;
- `stream`: an advanced internal stream owner may add, flush, and close;
- `detachedSocket`: HTTP ownership has ended and the returned socket belongs to
  the upgrade/low-level path.

Transfer itself does not commit a stream. Detachment does commit and is
irreversible. Framework writers reject any call after ownership transfer.

## State, commitment, and completion

The minimum state is `uncommitted`, `committed`, and `completed`. Streaming and
detachment are ownership modes rather than extra state values.

Experiments against Dart 3.13 `dart:io` established this conservative contract:

| Operation | Lifecycle effect |
| --- | --- |
| Set status or headers | Remains uncommitted; a mapped response can replace it |
| Transfer to stream | Ownership changes, but remains uncommitted |
| Flush an empty response | Remains uncommitted in the tested runtime |
| Add a non-empty body chunk | Committed before delegating to `HttpResponse.add` |
| Close without a body | Committed before delegating to `HttpResponse.close` |
| Detach the socket | Committed and ownership becomes detached |
| `HttpResponse.done` succeeds or fails | Completed |

`dart:io` sends headers when the response sink starts producing the response;
after that its status and headers cannot safely be changed. Oche deliberately
marks commitment at the call boundary immediately before the first non-empty
add or close. This can be slightly earlier than actual socket I/O, but never
later, so error mapping cannot race with an in-progress write. Empty chunks do
not commit. A flush after a body is already committed because the preceding
add committed it.

`close()` starts completion; it is not completion. Only `response.done`
settling changes state to `completed`, fires the completion hook, and removes
the request from active accounting. A `_closeStarted` bit makes repeated
stream closes harmless. A second framework completion remains a logic error,
not an idempotent success.

## Errors and double responses

Before commitment, expected application failures replace the pending response
with fixed 409 JSON and unexpected failures with fixed 500 JSON. Middleware
short-circuit uses the same single terminal boundary: it emits one 401 and the
handler is not invoked.

After commitment no status, headers, or mapped 500 are attempted. The first
failure is retained on the lifecycle controller and sent to the internal
`requestFailed` hook without exposing its message or stack to the client. If a
stream is still owned by Oche, close is initiated once so the connection does
not remain open indefinitely.

A second normal completion increments the diagnostic attempt count and throws
`ResponseLifecycleViolation`. The dispatch error boundary observes it as a
post-commit failure and preserves the first response. This detects flows such
as an after-hook trying to replace an already completed short-circuit while
preventing a second HTTP response.

## Streaming experiment

The internal stream owner writes chunks directly and never buffers the whole
body. Commitment occurs at the first non-empty chunk (or an empty close). Oche
initiates close after the asynchronous streaming work completes. Middleware
after-work that must precede close is therefore part of that work future; the
test records the after step before completion.

If streaming fails before its first chunk, ownership returns to the framework
and a generic 500 is still possible. If it fails after the first chunk, the
partial response is preserved, the failure is observed internally, and close
is initiated without a second response.

The generated diagnostic endpoint emits three chunks across asynchronous
boundaries. Its single Windows AOT correctness/overhead run at concurrency 10
reported 100% success, 5,260.09 requests/s, p50/p95/p99 of
1.825/2.453/2.927 ms, 14.67/18.95 MiB idle/peak RSS, and 124.33% process CPU.
Requests/s is not compared with a one-chunk raw response because the workloads
are not equivalent.

### SSE and WebSockets

SSE fits the stream owner: set `text/event-stream` before the first chunk,
write periodically, and flush after events. Shutdown treats an open SSE stream
as active until its HTTP response completes or the shutdown timeout forces the
connection closed.

WebSocket/low-level upgrade requires a distinct transfer. The experiment sends
a 101 response, calls `HttpResponse.detachSocket`, and verifies data on the
detached socket. HTTP completion ends active HTTP request accounting, while the
detached socket continues under its new owner. A future WebSocket feature must
track upgraded connections separately if application shutdown is expected to
drain them; it must not bypass lifecycle transfer and leave Oche believing it
still owns the response.

## Client disconnect and cancellation compatibility

`response.done`, body `add`, and `flush` are the available `dart:io` observation
points. A transport error completes the lifecycle, fires `requestFailed` once,
and fires `clientDisconnected`. On the tested Windows runtime, destroying a
client during a stream reliably released active accounting and kept the server
usable, but `response.done` could settle successfully after bytes had already
been accepted by the OS. Consequently disconnect classification is best-effort
and cannot be promised for every timing.

There is no cancellation API in this phase. A future request-abort signal can
be completed from observable sink/done errors and forced shutdown without
changing routing, middleware, or handler invocation. It cannot guarantee early
notification for a handler that has not written anything, because `dart:io`
does not expose a universal peer-disconnect future at that point. Cooperative
cancellation therefore remains a public-design question.

## Server lifecycle and shutdown

`ExperimentalServerRuntime` has five states: `created`, `starting`, `running`,
`stopping`, and `stopped`.

- Invalid ports fail before bind and leave the runtime stopped.
- Bind errors (including an occupied port) leave no retained `HttpServer` and
  leave the runtime stopped.
- Successful bind installs the request listener and transitions to running.
- A stop requested while bind is in progress waits for startup to settle, then
  closes a successfully bound server or returns after the startup failure.
- A runtime starts at most once.
- Repeated `stop()` calls return the identical shutdown future.

Graceful shutdown is:

1. transition to stopping and call `HttpServer.close(force: false)` to stop
   accepting new connections;
2. wait for the active counter to reach zero;
3. transition to stopped and complete shutdown.

The counter increments before request hooks and dispatch, and decrements only
after `response.done`. Sync, async, and streaming requests are therefore all
drained through the same rule; middleware cannot disappear midway through an
accepted pipeline. The hot path uses one integer. A single `Completer` is
created only when shutdown actually needs to wait; there are no locks and no
collection of per-request futures.

If the configured timeout expires, `HttpServer.close(force: true)` destroys
remaining connections, active accounting is discarded, `forcedShutdown` is
emitted, and the runtime stops. Late handler futures may still settle inside
the isolate, but lifecycle guards prevent them from creating a replacement
response. Forced shutdown explicitly does not promise after-hook completion.

The benchmark runner translates SIGINT into `stop()` and also SIGTERM where
the Dart platform exposes it (non-Windows in this experiment). Signal
subscriptions live in the thin runner, not the HTTP kernel. A future
application layer can replace this integration without changing lifecycle
semantics.

## Observability points

An optional internal interface exposes request started, response committed,
request completed, request failed, client disconnected, shutdown started,
shutdown completed, and forced shutdown. Calls pass the existing request,
error, and stack; no event object is allocated. With no hooks configured, the
fast path performs only nullable checks. Logging, tracing, metrics, sampling,
and their public APIs remain undecided.

## Windows AOT validation

The representative build used Windows 11 Pro build 26200, Intel Xeon E5-2680
v4, 28 logical CPUs, Dart 3.13.1 AOT, `oha` 1.16.0 on loopback, 100 routes,
middleware depth 3, 5 s warmup, 30 s measurement, 2 s cooldown, five
repetitions, and deterministic balanced ordering. Raw JSON remains Git-ignored.

| Workload | c | Phase 1E req/s | vs Phase 1D | vs raw | p99 ms | Idle/peak RSS MiB | CPU |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Sync | 10 | 5,319.46 | 99.45% | 97.45% | 2.741 | 14.67 / 18.94 | 121.59% |
| Sync | 100 | 5,390.84 | 95.87% | 98.52% | 25.061 | 14.69 / 55.51 | 122.16% |
| Sync | 500 | 5,770.51 | 101.45% | 100.59% | 117.109 | 14.68 / 84.77 | 125.07% |
| Async handler | 10 | 5,418.61 | 100.67% | 98.86% | 2.695 | 14.68 / 18.96 | 123.96% |
| Async handler | 100 | 5,442.58 | 101.32% | 99.03% | 24.904 | 14.67 / 55.49 | 121.04% |
| Async handler | 500 | 5,685.02 | 99.42% | 99.94% | 123.764 | 14.67 / 86.37 | 123.99% |

Five groups are 99.42–101.45% of the Phase 1D shared kernel. Sync/c100 was an
isolated 95.87% miss while remaining 98.52% of raw; individual results ranged
from 5,069 to 5,625 requests/s and Phase 1D itself reached 102.77% of raw. A
focused ten-repetition balanced repeat therefore tested that exact group. It
measured Phase 1E at 5,467.36 requests/s, 101.55% of Phase 1D and 102.25% of
raw, with p99 25.794 ms and 14.68/55.36 MiB idle/peak RSS. The larger repeat
passes the incremental budget and records rather than hides the matrix noise.

Across the resolved representative groups, Phase 1E is 99.42–101.55% of Phase
1D and 97.45–102.25% of raw, passing the 98% incremental and 95%
complete-stack engineering budgets. The normal candidate AOT executable is 6,618,624 bytes
versus 6,595,584 for Phase 1D (+0.35%); generated source is 88,013 versus
83,903 bytes (+4.90%).

Idle RSS differs from Phase 1D by only 0.01–0.02 MiB. In the final matrix,
peak RSS ranges from -0.15 to +0.71 MiB relative to Phase 1D; the focused
repeat is +0.16 MiB.
That is real process-level evidence but not a retained-object profile: the
controller, `Expando` association, and `response.done` observer allocate on
every accepted Phase 1E request, and VM heap growth/GC thresholds contribute
to peak RSS. No allocation-free claim is made. A profiler and native Linux
validation remain follow-up evidence, not reasons to obscure the measured
Windows result.

## Remaining risks

Native Linux lifecycle/performance validation is outstanding alongside ADR
0002. Disconnect timing is not universally observable before writes. Detached
connections need their own application-level shutdown policy. Forced shutdown
does not cancel arbitrary Dart futures. A profiler has not separated lifecycle
allocation rate from VM heap expansion. These constraints are explicit enough
to design a safe high-level API without deciding that API in Phase 1E.
