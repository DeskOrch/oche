import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:oche_codegen/src/annotation_reader.dart';
import 'package:oche_codegen/src/generation_error.dart';
import 'package:oche_codegen/src/model.dart';

final class ApplicationAnalyzer {
  const ApplicationAnalyzer();

  ApplicationModel analyze(ClassElement application) {
    final applicationAnnotation = readOcheAnnotation(
      application,
      'OcheApplication',
    );
    if (applicationAnnotation == null) {
      throw OcheGenerationError(
        '${application.displayName} is not annotated with @OcheApplication.',
      );
    }
    if (application.isPrivate) {
      throw OcheGenerationError(
        'Application root ${application.displayName} must be public so its '
        'generated bootstrap can be imported.',
      );
    }

    final controllerValues = applicationAnnotation
        .getField('controllers')
        ?.toListValue();
    if (controllerValues == null) {
      throw const OcheGenerationError(
        '@OcheApplication.controllers must be a constant list of controller '
        'types.',
      );
    }

    final controllers = <ControllerModel>[];
    final routes = <RouteModel>[];
    final seenControllers = <ClassElement>{};
    final importPrefixes = <String, String>{};
    for (var index = 0; index < controllerValues.length; index++) {
      final controller = _controllerElement(controllerValues[index]);
      if (controller == null) {
        throw OcheGenerationError(
          '${application.displayName} controllers[$index] is not a class. '
          'Reference a class annotated with @Controller.',
        );
      }
      if (!seenControllers.add(controller)) {
        throw OcheGenerationError(
          '${application.displayName} declares controller '
          '${controller.displayName} more than once. Remove the duplicate.',
        );
      }
      final controllerModel = _analyzeController(
        controller,
        index,
        routes,
        importPrefixes,
      );
      controllers.add(controllerModel);
    }
    _validateConflicts(routes);
    return ApplicationModel(
      className: application.displayName,
      controllers: List.unmodifiable(controllers),
      routes: List.unmodifiable(routes),
    );
  }

  ClassElement? _controllerElement(DartObject value) {
    final type = value.toTypeValue();
    final element = type?.element;
    return element is ClassElement ? element : null;
  }

  ControllerModel _analyzeController(
    ClassElement controller,
    int controllerIndex,
    List<RouteModel> routes,
    Map<String, String> importPrefixes,
  ) {
    final annotation = readOcheAnnotation(controller, 'Controller');
    if (annotation == null) {
      throw OcheGenerationError(
        '${controller.displayName} is listed in @OcheApplication.controllers '
        'but is not annotated with @Controller.',
      );
    }
    if (controller.isPrivate || !controller.isConstructable) {
      throw OcheGenerationError(
        'Controller ${controller.displayName} must be a public, constructable '
        'class.',
      );
    }
    final defaultConstructor = controller.constructors
        .where((constructor) => constructor.isDefaultConstructor)
        .firstOrNull;
    if (defaultConstructor == null) {
      throw OcheGenerationError(
        'Controller ${controller.displayName} needs an unnamed zero-argument '
        'constructor. Dependency injection is not supported in Phase 2A.',
      );
    }
    final library = controller.library;
    final libraryUri = library.uri.toString();
    final model = ControllerModel(
      className: controller.displayName,
      libraryUri: libraryUri,
      fieldName: '_controller$controllerIndex',
      importPrefix: importPrefixes.putIfAbsent(
        libraryUri,
        () => 'i${importPrefixes.length}',
      ),
    );
    final prefix = readStringField(annotation, 'path');
    _validateDeclaredPath(prefix, 'Controller ${controller.displayName}');

    for (final method in controller.methods) {
      final routeAnnotations = <(HttpVerb, DartObject)>[];
      for (final (verb, annotationName) in const <(HttpVerb, String)>[
        (HttpVerb.get, 'Get'),
        (HttpVerb.post, 'Post'),
        (HttpVerb.put, 'Put'),
        (HttpVerb.patch, 'Patch'),
        (HttpVerb.delete, 'Delete'),
      ]) {
        final routeAnnotation = readOcheAnnotation(method, annotationName);
        if (routeAnnotation != null) {
          routeAnnotations.add((verb, routeAnnotation));
        }
      }
      if (routeAnnotations.isEmpty) continue;
      if (routeAnnotations.length > 1) {
        throw OcheGenerationError(
          '${controller.displayName}.${method.displayName} has multiple HTTP '
          'method annotations. Declare exactly one route per method.',
        );
      }
      if (method.isStatic || method.isPrivate) {
        throw OcheGenerationError(
          'Route method ${controller.displayName}.${method.displayName} must '
          'be a public instance method.',
        );
      }
      final (verb, routeAnnotation) = routeAnnotations.single;
      final methodPath = readStringField(routeAnnotation, 'path');
      _validateDeclaredPath(
        methodPath,
        '${verb.wireName} ${controller.displayName}.${method.displayName}',
      );
      final fullPath = _combinePaths(prefix, methodPath);
      final segments = _parseSegments(fullPath);
      final parameters = _analyzeParameters(controller, method, segments);
      final returnKind = _returnKind(controller, method);
      routes.add(
        RouteModel(
          verb: verb,
          path: fullPath,
          segments: segments,
          controller: model,
          methodName: method.displayName,
          parameters: parameters,
          returnKind: returnKind,
          sourceDescription: '${controller.displayName}.${method.displayName}',
        ),
      );
    }
    return model;
  }

  List<ParameterModel> _analyzeParameters(
    ClassElement controller,
    MethodElement method,
    List<PathSegmentModel> segments,
  ) {
    final placeholderIndexes = <String, int>{};
    for (var index = 0; index < segments.length; index++) {
      final segment = segments[index];
      if (!segment.parameter) continue;
      if (placeholderIndexes.containsKey(segment.value)) {
        throw OcheGenerationError(
          'Route ${controller.displayName}.${method.displayName} declares '
          'placeholder "${segment.value}" more than once.',
        );
      }
      placeholderIndexes[segment.value] = index;
    }

    final bound = <String>{};
    final result = <ParameterModel>[];
    for (final parameter in method.formalParameters) {
      final annotation = readOcheAnnotation(parameter, 'Path');
      if (annotation == null) {
        throw OcheGenerationError(
          'Parameter "${parameter.displayName}" on '
          '${controller.displayName}.${method.displayName} needs @Path. '
          'Phase 2A supports path-bound parameters only.',
        );
      }
      final placeholder = readStringField(annotation, 'name');
      final segmentIndex = placeholderIndexes[placeholder];
      if (segmentIndex == null) {
        throw OcheGenerationError(
          '@Path("$placeholder") on '
          '${controller.displayName}.${method.displayName} is not present in '
          'route ${_pathForSegments(segments)}.',
        );
      }
      if (!bound.add(placeholder)) {
        throw OcheGenerationError(
          '${controller.displayName}.${method.displayName} binds '
          '@Path("$placeholder") more than once.',
        );
      }
      final type = parameter.type;
      final kind = switch (type) {
        final DartType type
            when type.isDartCoreString &&
                type.nullabilitySuffix == NullabilitySuffix.none =>
          PathValueKind.string,
        final DartType type
            when type.isDartCoreInt &&
                type.nullabilitySuffix == NullabilitySuffix.none =>
          PathValueKind.integer,
        _ => throw OcheGenerationError(
          '@Path("$placeholder") on '
          '${controller.displayName}.${method.displayName} has unsupported '
          'type ${type.getDisplayString()}. Use non-nullable String or int.',
        ),
      };
      result.add(
        ParameterModel(
          placeholder: placeholder,
          sourceName: parameter.displayName,
          kind: kind,
          segmentIndex: segmentIndex,
          isNamed: parameter.isNamed,
        ),
      );
    }

    for (final placeholder in placeholderIndexes.keys) {
      if (!bound.contains(placeholder)) {
        throw OcheGenerationError(
          'Route ${_pathForSegments(segments)} declares path parameter '
          '"$placeholder", but method '
          '${controller.displayName}.${method.displayName} has no '
          '@Path("$placeholder") parameter.',
        );
      }
    }
    return List.unmodifiable(result);
  }

  HandlerReturnKind _returnKind(ClassElement controller, MethodElement method) {
    final type = method.returnType;
    if (type is VoidType) return HandlerReturnKind.voidValue;
    if (type.isDartCoreString &&
        type.nullabilitySuffix == NullabilitySuffix.none) {
      return HandlerReturnKind.string;
    }
    if (_isUint8List(type)) return HandlerReturnKind.bytes;
    if (type is InterfaceType && type.isDartAsyncFuture) {
      final valueType = type.typeArguments.single;
      if (valueType is VoidType) return HandlerReturnKind.voidFuture;
      if (valueType.isDartCoreString &&
          valueType.nullabilitySuffix == NullabilitySuffix.none) {
        return HandlerReturnKind.stringFuture;
      }
      if (_isUint8List(valueType)) return HandlerReturnKind.bytesFuture;
    }
    throw OcheGenerationError(
      '${controller.displayName}.${method.displayName} returns unsupported '
      'type ${type.getDisplayString()}. Phase 2A supports String, '
      'Future<String>, void, Future<void>, Uint8List, and '
      'Future<Uint8List>.',
    );
  }

  bool _isUint8List(DartType type) =>
      type.nullabilitySuffix == NullabilitySuffix.none &&
      type.element?.displayName == 'Uint8List' &&
      type.element?.library?.uri.toString() == 'dart:typed_data';

  void _validateConflicts(List<RouteModel> routes) {
    final declarations = <String, RouteModel>{};
    for (final route in routes) {
      final key = '${route.verb.wireName} ${route.shape}';
      final previous = declarations[key];
      if (previous != null) {
        throw OcheGenerationError(
          'Conflicting route $key: ${previous.sourceDescription} declares '
          '${previous.path}, and ${route.sourceDescription} declares '
          '${route.path}. Rename the path or change its HTTP method.',
        );
      }
      declarations[key] = route;
    }
  }

  void _validateDeclaredPath(String path, String owner) {
    if (path.isEmpty) return;
    if (!path.startsWith('/')) {
      throw OcheGenerationError(
        '$owner path "$path" must be empty or start with "/".',
      );
    }
    if (path != '/' && path.endsWith('/')) {
      throw OcheGenerationError('$owner path "$path" must not end with "/".');
    }
    if (path.contains('//') ||
        path.contains(r'\') ||
        path.contains('?') ||
        path.contains('#') ||
        path.contains('%')) {
      throw OcheGenerationError(
        '$owner path "$path" contains unsupported routing syntax.',
      );
    }
    _parseSegments(path);
  }

  List<PathSegmentModel> _parseSegments(String path) {
    if (path.isEmpty || path == '/') return const [];
    final result = <PathSegmentModel>[];
    for (final segment in path.substring(1).split('/')) {
      if (segment.startsWith('{') && segment.endsWith('}')) {
        final name = segment.substring(1, segment.length - 1);
        if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(name)) {
          throw OcheGenerationError(
            'Route path "$path" has invalid placeholder "$segment". Use '
            'a Dart-style identifier such as {userId}.',
          );
        }
        result.add(PathSegmentModel.parameter(name));
      } else {
        if (segment.contains('{') ||
            segment.contains('}') ||
            segment == '.' ||
            segment == '..') {
          throw OcheGenerationError(
            'Route path "$path" has invalid segment "$segment".',
          );
        }
        result.add(PathSegmentModel.literal(segment));
      }
    }
    return List.unmodifiable(result);
  }

  String _combinePaths(String prefix, String methodPath) {
    if (prefix.isEmpty || prefix == '/') {
      return methodPath.isEmpty ? '/' : methodPath;
    }
    if (methodPath.isEmpty || methodPath == '/') return prefix;
    return '$prefix$methodPath';
  }

  String _pathForSegments(List<PathSegmentModel> segments) => segments.isEmpty
      ? '/'
      : '/${segments.map((segment) => segment.parameter ? '{${segment.value}}' : segment.value).join('/')}';
}
