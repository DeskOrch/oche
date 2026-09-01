# ADR 0007: First public routing API

- Status: Accepted
- Date: 2026-08-31

## Context

ADRs 0003 through 0006 establish private generated routing, specialized
handler execution, middleware composition, and response ownership. Oche now
needs the smallest coherent source model that can build a real application
without weakening those contracts.

The API remains experimental 0.x. Acceptance records the Phase 2A direction;
it does not promise source stability before a public stable release.

## Decision

Use an explicit annotation-driven application graph:

```dart
@Controller('/users')
final class UserController {
  @Get('/{id}')
  String find(@Path('id') int id) => 'User $id';
}

@OcheApplication(controllers: [UserController])
final class Application {}
```

- `@OcheApplication` lists controller types explicitly.
- `@Controller` supplies an optional compile-time prefix.
- `@Get`, `@Post`, `@Put`, `@Patch`, and `@Delete` declare method routes.
- `{name}` is the only placeholder syntax; `@Path('name')` binds a
  non-nullable `String` or `int`.
- Supported returns are `String`, `void`, `Uint8List`, and their exact
  `Future<T>` forms.
- Controllers need an unnamed constructor callable without arguments and are
  instantiated once by generated startup state.
- One generated `ApplicationOche` class provides the static bootstrap.
- Different methods on one path are valid; duplicate method/route shapes are
  build errors even when placeholder names differ.

The names read naturally as Dart metadata. `Path` is the likeliest import-name
collision, but path libraries are normally prefixed and the short binding form
is substantially clearer. The annotation classes leave room for future
optional fields without introducing a large family now.

## Rejected alternatives

- Runtime `app.get(...)` registration undermines the compile-time routing
  objective.
- Package/controller scanning hides the application boundary and complicates
  AOT reachability.
- A generic `Oche.run<Application>()` needs runtime lookup or a hidden registry.
- Dependency injection, body/query/header binding, JSON object mapping, public
  middleware, and low-level responses belong to later, separately reviewed
  phases.

## Evidence

The real `examples/hello_oche` application uses only this public API and its
generated bootstrap. Generator tests cover deterministic direct-call output,
literal precedence, return specialization, forbidden dynamic shapes, route
conflicts, binding mistakes, unsupported types, invalid controllers, and
multiple roots. Process-level tests exercise the generated server over HTTP.

No unresolved API concern requires reverting to runtime registration. The
surface is therefore Accepted as the experimental Phase 2A model.

## Consequences

Users gain a small application syntax but intentionally cannot customize most
HTTP inputs or responses yet. Generator diagnostics are part of the product
contract. Future API work must extend this model without adding reflection,
per-request descriptors, or mandatory dynamic invocation.
