# Getting started

Oche is experimental pre-alpha software. Phase 2A provides one deliberately
small vertical slice: compile-time controllers, typed path parameters, and a
generated `dart:io` application. It is not production-ready.

## Prerequisites

- Dart SDK 3.13 or later;
- a clone of this repository.

Install the workspace dependencies from the repository root:

```console
dart pub get
```

## Declare an application

The complete runnable example is in `examples/hello_oche`. Its application
source uses only the public `package:oche/oche.dart` API:

```dart
import 'package:oche/oche.dart';

@Controller('/users')
final class UserController {
  @Get('/{id}')
  String find(@Path('id') int id) => 'User $id';
}

@OcheApplication(controllers: [UserController])
final class Application {}
```

Application roots are explicit. Every listed controller must have
`@Controller` and an unnamed constructor callable with no arguments. Oche
constructs each controller once, when the generated application initializes.
Dependency injection is not part of Phase 2A.

The supported route annotations are `@Get`, `@Post`, `@Put`, `@Patch`, and
`@Delete`. A controller prefix and method path are combined during generation.
Path placeholders use `{name}` and bind to non-nullable `String` or `int`
parameters through `@Path('name')`.

Handlers may return only:

- `String` or `Future<String>`;
- `void` or `Future<void>`;
- `Uint8List` or `Future<Uint8List>`.

Strings become `text/plain` 200 responses, bytes become
`application/octet-stream` 200 responses, and void becomes 204. JSON object
serialization and direct response ownership are intentionally absent.

## Generate and run

Run the production builder in the example package:

```console
cd examples/hello_oche
dart run build_runner build
dart run bin/server.dart
```

The build creates `lib/application.oche.dart` beside the source. It is a normal,
inspectable Dart library and is tracked in this repository for the example.
Open another terminal and try:

```console
curl http://127.0.0.1:8080/hello
curl http://127.0.0.1:8080/hello/Guilherme
curl http://127.0.0.1:8080/users/42
```

For incremental development, keep a watcher running:

```console
dart run build_runner watch
```

To exercise generation from a clean build state:

```console
dart run build_runner clean
dart run build_runner build
```

The generated bootstrap is statically named after the application root:

```dart
import 'package:hello_oche/application.oche.dart';

Future<void> main() => ApplicationOche.run();
```

There is no `Oche.run<Application>()`, global registry, controller scan, or
runtime route registration.

## Build AOT and test

From the repository root:

```console
dart compile exe examples/hello_oche/bin/server.dart \
  -o build/phase2a/hello_oche
dart test
dart analyze
dart format --output=none --set-exit-if-changed .
```

On PowerShell, use a backtick instead of `\` for line continuation, or keep
the compile command on one line.

Generator errors identify the invalid controller or method and describe the
supported fix. Correct generation is required before the generated bootstrap
can be imported.
