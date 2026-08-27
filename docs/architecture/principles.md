# Architectural principles

Oche's intended direction is constrained by these principles. They are not a
commitment to specific high-level APIs in Phase 0.

1. Prefer compile-time work over runtime work.
2. Treat native/AOT execution as the production target.
3. Do not use runtime reflection.
4. Do not scan packages or a classpath at runtime.
5. Do not discover dependency graphs at runtime.
6. Prefer generated static code over dynamic indirection.
7. Keep runtime abstractions minimal and measurable.
8. Keep features modular so unused features tree-shake effectively.
9. Treat performance as an architectural requirement, not an afterthought.
10. Preserve strong developer ergonomics without buying them with excessive
    runtime complexity.

## Phase 0 interpretation

The principles currently guide what is *not* built. Package directories are
only repository boundaries. There are no speculative controller, injection,
ORM, authentication, validation, or plugin abstractions. The raw `dart:io` and
Relic servers deliberately expose the same small workload so their overhead can
be measured before an HTTP foundation is selected.
