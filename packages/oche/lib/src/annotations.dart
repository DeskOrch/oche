/// Marks the explicit compile-time root of an Oche application.
///
/// The production generator follows only [controllers]. Oche never discovers
/// controllers by scanning at runtime.
final class OcheApplication {
  const OcheApplication({required this.controllers});

  final List<Type> controllers;
}

/// Marks a class as an Oche controller with an optional path prefix.
final class Controller {
  const Controller([this.path = '']);

  final String path;
}

/// Declares a GET route on a controller method.
final class Get {
  const Get([this.path = '']);

  final String path;
}

/// Declares a POST route on a controller method.
final class Post {
  const Post([this.path = '']);

  final String path;
}

/// Declares a PUT route on a controller method.
final class Put {
  const Put([this.path = '']);

  final String path;
}

/// Declares a PATCH route on a controller method.
final class Patch {
  const Patch([this.path = '']);

  final String path;
}

/// Declares a DELETE route on a controller method.
final class Delete {
  const Delete([this.path = '']);

  final String path;
}

/// Binds a method parameter to a named `{placeholder}` in its route.
final class Path {
  const Path(this.name);

  final String name;
}
