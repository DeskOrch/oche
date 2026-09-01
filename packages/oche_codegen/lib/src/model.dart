enum HttpVerb {
  get('GET'),
  post('POST'),
  put('PUT'),
  patch('PATCH'),
  delete('DELETE');

  const HttpVerb(this.wireName);

  final String wireName;
}

enum HandlerReturnKind {
  string,
  stringFuture,
  voidValue,
  voidFuture,
  bytes,
  bytesFuture,
}

enum PathValueKind { string, integer }

final class PathSegmentModel {
  const PathSegmentModel.literal(this.value) : parameter = false;

  const PathSegmentModel.parameter(this.value) : parameter = true;

  final String value;
  final bool parameter;

  String get shape => parameter ? '{}' : value;
}

final class ParameterModel {
  const ParameterModel({
    required this.placeholder,
    required this.sourceName,
    required this.kind,
    required this.segmentIndex,
    required this.isNamed,
  });

  final String placeholder;
  final String sourceName;
  final PathValueKind kind;
  final int segmentIndex;
  final bool isNamed;
}

final class ControllerModel {
  const ControllerModel({
    required this.className,
    required this.libraryUri,
    required this.fieldName,
    required this.importPrefix,
  });

  final String className;
  final String libraryUri;
  final String fieldName;
  final String importPrefix;
}

final class RouteModel {
  const RouteModel({
    required this.verb,
    required this.path,
    required this.segments,
    required this.controller,
    required this.methodName,
    required this.parameters,
    required this.returnKind,
    required this.sourceDescription,
  });

  final HttpVerb verb;
  final String path;
  final List<PathSegmentModel> segments;
  final ControllerModel controller;
  final String methodName;
  final List<ParameterModel> parameters;
  final HandlerReturnKind returnKind;
  final String sourceDescription;

  String get shape => '/${segments.map((segment) => segment.shape).join('/')}';
}

final class ApplicationModel {
  const ApplicationModel({
    required this.className,
    required this.controllers,
    required this.routes,
  });

  final String className;
  final List<ControllerModel> controllers;
  final List<RouteModel> routes;
}

final class RouteTreeNode {
  final Map<String, RouteTreeNode> literals = <String, RouteTreeNode>{};
  RouteTreeNode? parameter;
  final List<RouteModel> endpoints = <RouteModel>[];
}
