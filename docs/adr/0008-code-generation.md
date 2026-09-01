# ADR 0008: Production code generation

- Status: Accepted
- Date: 2026-08-31

## Context

The first public API needs production generation compatible with Dart 3.13,
incremental development, AOT, useful semantic diagnostics, and inspectable
source. A custom parser and runtime metadata discovery are excluded.

## Decision

Implement an auto-applied `package:build` builder, run by `build_runner`, over
the analyzer's resolved element and constant-value APIs.

- Input `application.dart` produces standalone `application.oche.dart` only
  when that library declares an application root.
- Output is written to the source tree, formatted, deterministic, and directly
  importable.
- The generator owns the complete standalone file rather than participating in
  a shared `.g.dart` part.
- Semantic analysis follows only controller types in the root annotation.
- Validation finishes before emission; invalid graphs fail the build.
- Generated code imports the narrow generator-facing Oche runtime library and
  emits segmented typed dispatch directly.

`source_gen` was considered. Its annotation and part builders are useful
defaults, but Oche needs application-wide conflict analysis and a complete
standalone library. Direct `package:build` is a smaller appropriate layer and
still uses the official analyzer/build ecosystem.

## Evidence

The builder runs under `build_runner` 2.16 with `package:build` 4.0 and analyzer
14.1 on Dart 3.13.1. Build and watch mode have dependency-aware inputs, emitted
source passes repository analysis, deterministic generation is tested, and the
example compiles to AOT. A clean regeneration produced deterministic output;
the generated example is 6,803 bytes/206 lines and its native executable is
6.208 MiB. Architecture-inspection tests exclude reflection, runtime
registration, parameter maps, and dynamic invocation. The full Windows AOT
evidence and focused Phase 1E comparison are recorded in
[`../architecture/code-generation.md`](../architecture/code-generation.md).

## Consequences

Applications add `oche_codegen` and `build_runner` as development dependencies
and explicitly import the generated library. Generated files are visible and
may be reviewed or checked in according to project policy. Builder startup has
a noticeable first-run compilation cost; subsequent incremental builds reuse
the build graph. A future CLI may wrap these commands without changing the
generator contract.
