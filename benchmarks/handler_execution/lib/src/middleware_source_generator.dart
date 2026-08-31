import 'package:handler_execution_benchmark/middleware_execution_benchmark.dart';

String generateMiddlewareSource(
  MiddlewareCandidate candidate,
  int routeCount,
  int depth,
) {
  if (routeCount != 10 && routeCount != 100 && routeCount != 1000) {
    throw ArgumentError.value(routeCount, 'routeCount');
  }
  if (!middlewareDepths.contains(depth)) {
    throw ArgumentError.value(depth, 'depth');
  }
  if (candidate == MiddlewareCandidate.phase1b && depth != 0) {
    throw ArgumentError.value(depth, 'depth', 'Phase 1B baseline is depth 0.');
  }

  final out = StringBuffer()
    ..writeln('// GENERATED BENCHMARK SOURCE. DO NOT EDIT.')
    ..writeln("import 'dart:io';")
    ..writeln()
    ..writeln(
      "import 'package:handler_execution_benchmark/"
      "handler_execution_benchmark.dart';",
    )
    ..writeln(
      "import 'package:handler_execution_benchmark/"
      "middleware_execution_benchmark.dart';",
    )
    ..writeln()
    ..writeln("const generatedCandidate = '${candidate.name}';")
    ..writeln('const generatedRouteCount = $routeCount;')
    ..writeln('const generatedMiddlewareDepth = $depth;');
  if (candidate == MiddlewareCandidate.runtime) {
    out.writeln(
      'final runtimeMiddlewareSteps = '
      'buildRuntimeMiddlewareSteps(generatedMiddlewareDepth);',
    );
  }
  out
    ..writeln()
    ..writeln('Future<void> main(List<String> arguments) =>')
    ..writeln('    runHandlerBenchmarkServer(')
    ..writeln('      arguments,')
    ..writeln(
      "      name: 'middleware-\$generatedCandidate-"
      "\$generatedRouteCount-d\$generatedMiddlewareDepth',",
    )
    ..writeln('      dispatch: generatedMiddlewareDispatch,')
    ..writeln('    );')
    ..writeln();

  _writeAdapters(out, candidate, routeCount, depth);
  _writeDispatch(out, routeCount);
  return out.toString();
}

/// Generates the Phase 1E candidate from the accepted Phase 1D shared kernel.
///
/// Routing, binding, and middleware specialization remain byte-for-byte the
/// Phase 1D shape. Only the server boundary and terminal response operations
/// are substituted, keeping the performance comparison narrowly scoped.
String generateResponseLifecycleSource({int routeCount = 100, int depth = 3}) {
  var source = generateMiddlewareSource(
    MiddlewareCandidate.shared,
    routeCount,
    depth,
  );
  source = source.replaceFirst(
    "import 'package:handler_execution_benchmark/"
        "middleware_execution_benchmark.dart';",
    "import 'package:handler_execution_benchmark/"
        "middleware_execution_benchmark.dart';\n"
        "import 'package:handler_execution_benchmark/"
        "response_lifecycle_benchmark.dart';",
  );
  source = source
      .replaceFirst(
        "const generatedCandidate = 'shared';",
        "const generatedCandidate = 'responseLifecycle';",
      )
      .replaceFirst(
        'runHandlerBenchmarkServer(',
        'runResponseLifecycleBenchmarkServer(',
      );

  const responseOperations = <String, String>{
    'executeMiddlewareAsyncResponse(':
        'executeLifecycleMiddlewareAsyncResponse(',
    'writeMiddlewareUnauthorized(': 'writeLifecycleMiddlewareUnauthorized(',
    'writeMiddlewareOrder(': 'writeLifecycleMiddlewareOrder(',
    'writeJsonStringResult(': 'writeLifecycleJsonStringResult(',
    'writeTextResult(': 'writeLifecycleTextResult(',
    'writeNotFound(': 'writeLifecycleNotFound(',
    'writeInvalidParameter(': 'writeLifecycleInvalidParameter(',
    'writeMethodNotAllowed(': 'writeLifecycleMethodNotAllowed(',
  };
  for (final replacement in responseOperations.entries) {
    source = source.replaceAll(replacement.key, replacement.value);
  }

  source = source.replaceFirst(
    'void generatedMiddlewareDispatch(HttpRequest request) {',
    '''void generatedMiddlewareDispatch(HttpRequest request) {
  if (request.uri.path == '/stream') {
    _streamRoute(request);
    return;
  }''',
  );
  return '''$source
void _streamRoute(HttpRequest request) {
  if (request.method != 'GET') {
    writeLifecycleMethodNotAllowed(request, const ['GET']);
    return;
  }
  final stream = transferLifecycleResponseToStream(
    request,
    contentType: ContentType.text,
  );
  executeLifecycleStreaming(stream, _writeStreamingChunks(stream));
}

Future<void> _writeStreamingChunks(InternalStreamingResponse stream) async {
  stream.write('chunk 1\\n');
  await Future<void>.delayed(Duration.zero);
  stream.write('chunk 2\\n');
  await Future<void>.delayed(Duration.zero);
  stream.write('chunk 3\\n');
}
''';
}

void _writeDispatch(StringBuffer out, int routeCount) {
  out
    ..writeln('void generatedMiddlewareDispatch(HttpRequest request) {')
    ..writeln('  final segments = handlerPathSegments(request.uri);')
    ..writeln('  if (segments == null) {')
    ..writeln('    writeNotFound(request);')
    ..writeln('    return;')
    ..writeln('  }')
    ..writeln('  switch (segments.length) {')
    ..writeln('    case 1:')
    ..writeln('      switch (segments[0]) {')
    ..writeln("        case 'health':")
    ..writeln('          _healthRoute(request);')
    ..writeln('          return;')
    ..writeln("        case 'status':")
    ..writeln('          _statusRoute(request);')
    ..writeln('          return;')
    ..writeln("        case 'payload':")
    ..writeln('          _payloadRoute(request);')
    ..writeln('          return;')
    ..writeln('      }')
    ..writeln('      break;')
    ..writeln('    case 2:')
    ..writeln('      switch (segments[0]) {')
    ..writeln("        case 'users':")
    ..writeln('          final id = int.tryParse(segments[1]);')
    ..writeln('          if (id == null) {')
    ..writeln("            writeInvalidParameter(request, 'id');")
    ..writeln('            return;')
    ..writeln('          }')
    ..writeln('          _usersRoute(request, id);')
    ..writeln('          return;')
    ..writeln("        case 'errors':")
    ..writeln('          _errorsRoute(request, segments[1]);')
    ..writeln('          return;')
    ..writeln("        case 'request':")
    ..writeln('          _requestRoute(request, segments[1]);')
    ..writeln('          return;')
    ..writeln('      }')
    ..writeln('      break;')
    ..writeln('    case 3:')
    ..writeln("      if (segments[0] == 'async' ||")
    ..writeln("          segments[0] == 'middleware') {")
    ..writeln('        final id = int.tryParse(segments[2]);')
    ..writeln('        if (id == null) {')
    ..writeln("          writeInvalidParameter(request, 'id');")
    ..writeln('          return;')
    ..writeln('        }')
    ..writeln("        if (segments[0] == 'async') {")
    ..writeln('          _asyncRoute(request, segments[1], id);')
    ..writeln('        } else {')
    ..writeln('          _middlewareRoute(request, segments[1], id);')
    ..writeln('        }')
    ..writeln('        return;')
    ..writeln('      }');
  _writeSyntheticDispatch(out, routeCount, 0);
  out
    ..writeln('      break;')
    ..writeln('    case 4:')
    ..writeln("      if (segments[0] == 'orders' &&")
    ..writeln("          segments[2] == 'items') {")
    ..writeln('        final userId = int.tryParse(segments[1]);')
    ..writeln('        final orderId = int.tryParse(segments[3]);')
    ..writeln('        if (userId == null || orderId == null) {')
    ..writeln("          writeInvalidParameter(request, 'id');")
    ..writeln('          return;')
    ..writeln('        }')
    ..writeln('        _ordersRoute(request, userId, orderId);')
    ..writeln('        return;')
    ..writeln('      }')
    ..writeln("      if (segments[0] == 'catalog' &&")
    ..writeln("          segments[2] == 'items') {")
    ..writeln('        final id = int.tryParse(segments[3]);')
    ..writeln('        if (id == null) {')
    ..writeln("          writeInvalidParameter(request, 'id');")
    ..writeln('          return;')
    ..writeln('        }')
    ..writeln('        _catalogRoute(request, segments[1], id);')
    ..writeln('        return;')
    ..writeln('      }');
  _writeSyntheticDispatch(out, routeCount, 1);
  out
    ..writeln('      break;')
    ..writeln('    case 6:');
  _writeSyntheticDispatch(out, routeCount, 2);
  out
    ..writeln('      break;')
    ..writeln('  }')
    ..writeln('  writeNotFound(request);')
    ..writeln('}');
}

void _writeSyntheticDispatch(StringBuffer out, int routeCount, int shape) {
  final routes = <int>[
    for (var route = 10; route < routeCount; route++)
      if ((route - 10) % 3 == shape) route,
  ];
  if (routes.isEmpty) return;
  out
    ..writeln("      if (segments[0] == 'generated') {")
    ..writeln('        switch (segments[1]) {');
  for (final route in routes) {
    out.writeln("          case 'r${route - 10}':");
    if (shape == 0) {
      out
        ..writeln("            if (segments[2] != 'literal') {")
        ..writeln('              break;')
        ..writeln('            }')
        ..writeln('            _syntheticRoute$route(request);');
    } else if (shape == 1) {
      out
        ..writeln("            if (segments[2] != 'items') {")
        ..writeln('              break;')
        ..writeln('            }')
        ..writeln('            final id = int.tryParse(segments[3]);')
        ..writeln('            if (id == null) {')
        ..writeln("              writeInvalidParameter(request, 'id');")
        ..writeln('              return;')
        ..writeln('            }')
        ..writeln('            _syntheticRoute$route(request, id);');
    } else {
      out
        ..writeln("            if (segments[2] != 'items' ||")
        ..writeln("                segments[4] != 'children') {")
        ..writeln('              break;')
        ..writeln('            }')
        ..writeln('            final id = int.tryParse(segments[3]);')
        ..writeln('            final childId = int.tryParse(segments[5]);')
        ..writeln('            if (id == null || childId == null) {')
        ..writeln("              writeInvalidParameter(request, 'id');")
        ..writeln('              return;')
        ..writeln('            }')
        ..writeln('            _syntheticRoute$route(request, id, childId);');
    }
    out.writeln('            return;');
  }
  out
    ..writeln('        }')
    ..writeln('      }');
}

void _writeAdapters(
  StringBuffer out,
  MiddlewareCandidate candidate,
  int routeCount,
  int depth,
) {
  out
    ..writeln('void _healthRoute(HttpRequest request) {')
    ..writeln("  if (request.method == 'GET') {")
    ..writeln('    writeTextResult(request, healthHandler());')
    ..writeln('  } else {')
    ..writeln("    writeMethodNotAllowed(request, const ['GET']);")
    ..writeln('  }')
    ..writeln('}')
    ..writeln();
  _writeSimpleSyncRoute(
    out,
    candidate,
    depth,
    name: 'status',
    invocation: 'statusHandler()',
  );
  _writeSimpleSyncRoute(
    out,
    candidate,
    depth,
    name: 'payload',
    invocation: "'{\"payload\":true}'",
  );
  _writeUsersRoute(out, candidate, depth);
  _writeErrorsRoute(out, candidate, depth);
  _writeRequestRoute(out, candidate, depth);
  _writeAsyncRoute(out, candidate, depth);
  _writeMiddlewareRoute(out, candidate, depth);
  _writeOrdersRoute(out, candidate, depth);
  _writeCatalogRoute(out, candidate, depth);
  for (var route = 10; route < routeCount; route++) {
    _writeSyntheticRoute(out, candidate, depth, route);
  }
  if (candidate == MiddlewareCandidate.generated) {
    for (final profile in const [
      MiddlewareProfile.asyncHandlerSyncMiddleware,
      MiddlewareProfile.asyncMiddleware,
      MiddlewareProfile.mixed,
      MiddlewareProfile.shortAsync,
      MiddlewareProfile.errorAsync,
    ]) {
      _writeGeneratedAsyncExecutor(out, depth, profile);
    }
  } else if (candidate == MiddlewareCandidate.shared) {
    _writeSharedAsyncExecutor(out, depth);
  }
}

void _writeSimpleSyncRoute(
  StringBuffer out,
  MiddlewareCandidate candidate,
  int depth, {
  required String name,
  required String invocation,
}) {
  out
    ..writeln(
      'void _$name'
      'Route(HttpRequest request) {',
    )
    ..writeln("  if (request.method != 'GET') {")
    ..writeln("    writeMethodNotAllowed(request, const ['GET']);")
    ..writeln('    return;')
    ..writeln('  }');
  _writeSyncPipeline(
    out,
    candidate,
    depth,
    invocation,
    MiddlewareProfile.syncContinue,
  );
  out
    ..writeln('}')
    ..writeln();
}

void _writeUsersRoute(
  StringBuffer out,
  MiddlewareCandidate candidate,
  int depth,
) {
  out
    ..writeln('void _usersRoute(HttpRequest request, int id) {')
    ..writeln("  if (request.method != 'GET') {")
    ..writeln("    writeMethodNotAllowed(request, const ['GET']);")
    ..writeln('    return;')
    ..writeln('  }');
  _writeSyncPipeline(
    out,
    candidate,
    depth,
    'middlewareSyncHandler(id)',
    MiddlewareProfile.syncContinue,
  );
  out
    ..writeln('}')
    ..writeln();
}

void _writeErrorsRoute(
  StringBuffer out,
  MiddlewareCandidate candidate,
  int depth,
) {
  out
    ..writeln('void _errorsRoute(HttpRequest request, String kind) {')
    ..writeln("  if (request.method != 'GET') {")
    ..writeln("    writeMethodNotAllowed(request, const ['GET']);")
    ..writeln('    return;')
    ..writeln('  }');
  _writeSyncPipeline(
    out,
    candidate,
    depth,
    'errorHandler(kind)',
    MiddlewareProfile.syncContinue,
  );
  out
    ..writeln('}')
    ..writeln();
}

void _writeRequestRoute(
  StringBuffer out,
  MiddlewareCandidate candidate,
  int depth,
) {
  out
    ..writeln('void _requestRoute(HttpRequest request, String kind) {')
    ..writeln("  if (request.method != 'GET') {")
    ..writeln("    writeMethodNotAllowed(request, const ['GET']);")
    ..writeln('    return;')
    ..writeln('  }');
  _writeSyncPipeline(
    out,
    candidate,
    depth,
    "kind == 'raw' ? rawRequestHandler(request) : statusHandler()",
    MiddlewareProfile.syncContinue,
  );
  out
    ..writeln('}')
    ..writeln();
}

void _writeAsyncRoute(
  StringBuffer out,
  MiddlewareCandidate candidate,
  int depth,
) {
  out
    ..writeln('void _asyncRoute(HttpRequest request, String kind, int id) {')
    ..writeln("  if (request.method != 'GET') {")
    ..writeln("    writeMethodNotAllowed(request, const ['GET']);")
    ..writeln('    return;')
    ..writeln('  }')
    ..writeln("  if (kind == 'sync') {");
  _writeAsyncPipelineCall(
    out,
    candidate,
    depth,
    'middlewareImmediateAsyncHandler(id)',
    MiddlewareProfile.asyncHandlerSyncMiddleware,
    indent: '    ',
  );
  out
    ..writeln('    return;')
    ..writeln('  }')
    ..writeln("  if (kind == 'async') {");
  _writeAsyncPipelineCall(
    out,
    candidate,
    depth,
    'middlewareImmediateAsyncHandler(id)',
    MiddlewareProfile.asyncMiddleware,
    indent: '    ',
  );
  out
    ..writeln('    return;')
    ..writeln('  }')
    ..writeln("  if (kind == 'mixed') {");
  _writeAsyncPipelineCall(
    out,
    candidate,
    depth,
    'middlewareBoundaryAsyncHandler(id)',
    MiddlewareProfile.mixed,
    indent: '    ',
  );
  out
    ..writeln('    return;')
    ..writeln('  }')
    ..writeln('  writeNotFound(request);')
    ..writeln('}')
    ..writeln();
}

void _writeMiddlewareRoute(
  StringBuffer out,
  MiddlewareCandidate candidate,
  int depth,
) {
  out
    ..writeln(
      'void _middlewareRoute(HttpRequest request, String kind, int id) {',
    )
    ..writeln("  if (request.method != 'GET') {")
    ..writeln("    writeMethodNotAllowed(request, const ['GET']);")
    ..writeln('    return;')
    ..writeln('  }')
    ..writeln("  if (kind == 'short-async') {");
  _writeAsyncPipelineCall(
    out,
    candidate,
    depth,
    'middlewareImmediateAsyncHandler(id)',
    MiddlewareProfile.shortAsync,
    indent: '    ',
  );
  out
    ..writeln('    return;')
    ..writeln('  }')
    ..writeln("  if (kind == 'error-async') {");
  _writeAsyncPipelineCall(
    out,
    candidate,
    depth,
    'middlewareImmediateAsyncHandler(id)',
    MiddlewareProfile.errorAsync,
    indent: '    ',
  );
  out
    ..writeln('    return;')
    ..writeln('  }')
    ..writeln('  final profile = switch (kind) {')
    ..writeln("    'short-sync' => MiddlewareProfile.shortSync,")
    ..writeln("    'order' => MiddlewareProfile.order,")
    ..writeln("    'error-before' => MiddlewareProfile.errorBefore,")
    ..writeln("    'error-handler' => MiddlewareProfile.errorHandler,")
    ..writeln("    'error-after' => MiddlewareProfile.errorAfter,")
    ..writeln("    'state-none' => MiddlewareProfile.stateNone,")
    ..writeln("    'state-lazy' => MiddlewareProfile.stateLazy,")
    ..writeln("    'state-typed' => MiddlewareProfile.stateTyped,")
    ..writeln("    'instance' => MiddlewareProfile.instance,")
    ..writeln('    _ => null,')
    ..writeln('  };')
    ..writeln('  if (profile == null) {')
    ..writeln('    writeNotFound(request);')
    ..writeln('    return;')
    ..writeln('  }')
    ..writeln(
      '  final trace = profile == MiddlewareProfile.order '
      '? <String>[] : null;',
    );
  if (candidate == MiddlewareCandidate.runtime) {
    out
      ..writeln('  final invocation = switch (profile) {')
      ..writeln(
        '    MiddlewareProfile.errorHandler => '
        '() => middlewareFailingHandler(id),',
      )
      ..writeln(
        '    MiddlewareProfile.stateNone || '
        'MiddlewareProfile.stateLazy || '
        'MiddlewareProfile.stateTyped => '
        '() => executeStateExperiment(id, profile),',
      )
      ..writeln('    _ => () => middlewareSyncHandler(id),')
      ..writeln('  };');
  }
  final invocation = candidate == MiddlewareCandidate.runtime
      ? 'invocation()'
      : '''switch (profile) {
    MiddlewareProfile.errorHandler => middlewareFailingHandler(id),
    MiddlewareProfile.stateNone ||
    MiddlewareProfile.stateLazy ||
    MiddlewareProfile.stateTyped => executeStateExperiment(id, profile),
    _ => middlewareSyncHandler(id),
  }''';
  _writeSyncPipeline(
    out,
    candidate,
    depth,
    invocation,
    MiddlewareProfile.syncContinue,
    dynamicProfile: true,
    traceExpression: 'trace',
  );
  out
    ..writeln('}')
    ..writeln();
}

void _writeOrdersRoute(
  StringBuffer out,
  MiddlewareCandidate candidate,
  int depth,
) {
  out
    ..writeln(
      'void _ordersRoute(HttpRequest request, int userId, int orderId) {',
    )
    ..writeln("  if (request.method != 'GET') {")
    ..writeln("    writeMethodNotAllowed(request, const ['GET']);")
    ..writeln('    return;')
    ..writeln('  }');
  _writeSyncPipeline(
    out,
    candidate,
    depth,
    'middlewareTwoIntHandler(userId, orderId)',
    MiddlewareProfile.syncContinue,
  );
  out
    ..writeln('}')
    ..writeln();
}

void _writeCatalogRoute(
  StringBuffer out,
  MiddlewareCandidate candidate,
  int depth,
) {
  out
    ..writeln('void _catalogRoute(HttpRequest request, String sku, int id) {')
    ..writeln("  if (request.method != 'GET') {")
    ..writeln("    writeMethodNotAllowed(request, const ['GET']);")
    ..writeln('    return;')
    ..writeln('  }');
  _writeSyncPipeline(
    out,
    candidate,
    depth,
    "'{\"sku\":\"\$sku\",\"id\":\$id}'",
    MiddlewareProfile.syncContinue,
  );
  out
    ..writeln('}')
    ..writeln();
}

void _writeSyntheticRoute(
  StringBuffer out,
  MiddlewareCandidate candidate,
  int depth,
  int route,
) {
  out
    ..writeln('void _syntheticRoute$route(')
    ..writeln('  HttpRequest request, [')
    ..writeln('  int? first,')
    ..writeln('  int? second,')
    ..writeln(']) {')
    ..writeln("  if (request.method != 'GET') {")
    ..writeln("    writeMethodNotAllowed(request, const ['GET']);")
    ..writeln('    return;')
    ..writeln('  }');
  _writeSyncPipeline(
    out,
    candidate,
    depth,
    'middlewareSyntheticHandler($route, first, second)',
    MiddlewareProfile.syncContinue,
  );
  out
    ..writeln('}')
    ..writeln();
}

void _writeSyncPipeline(
  StringBuffer out,
  MiddlewareCandidate candidate,
  int depth,
  String invocation,
  MiddlewareProfile profile, {
  bool dynamicProfile = false,
  String traceExpression = 'null',
}) {
  final profileExpression = dynamicProfile
      ? 'profile'
      : 'MiddlewareProfile.${profile.name}';
  final hasTrace = traceExpression != 'null';
  switch (candidate) {
    case MiddlewareCandidate.phase1b:
      if (hasTrace) out.writeln("  $traceExpression?.add('handler');");
      out.writeln('  final result = $invocation;');
    case MiddlewareCandidate.generated:
      for (var index = 0; index < depth; index++) {
        out
          ..writeln('  final decision$index = generatedMiddlewareBefore(')
          ..writeln('    request,')
          ..writeln('    $index,')
          ..writeln('    $profileExpression,')
          ..writeln('    $traceExpression,')
          ..writeln('  );')
          ..writeln(
            '  if (decision$index == MiddlewareDecision.unauthorized) {',
          );
        for (var outer = index - 1; outer >= 0; outer--) {
          out.writeln(
            '    generatedMiddlewareAfter(request, $outer, '
            '$profileExpression, $traceExpression);',
          );
        }
        out
          ..writeln('    writeMiddlewareUnauthorized(request);')
          ..writeln('    return;')
          ..writeln('  }');
      }
      if (hasTrace) out.writeln("  $traceExpression?.add('handler');");
      out.writeln('  final result = $invocation;');
      for (var index = depth - 1; index >= 0; index--) {
        out.writeln(
          '  generatedMiddlewareAfter(request, $index, '
          '$profileExpression, $traceExpression);',
        );
      }
    case MiddlewareCandidate.runtime:
      out
        ..writeln('  final result = executeRuntimeSyncPipeline(')
        ..writeln('    request,')
        ..writeln('    runtimeMiddlewareSteps,')
        ..writeln('    $profileExpression,')
        ..writeln('    () => $invocation,')
        ..writeln('    trace: $traceExpression,')
        ..writeln('  );')
        ..writeln('  if (result == null) {')
        ..writeln('    writeMiddlewareUnauthorized(request);')
        ..writeln('    return;')
        ..writeln('  }');
    case MiddlewareCandidate.shared:
      if (depth > 0) {
        out
          ..writeln('  if (!enterSharedSyncPipeline$depth(')
          ..writeln('    request,')
          ..writeln('    $profileExpression,')
          ..writeln('    $traceExpression,')
          ..writeln('  )) {')
          ..writeln('    writeMiddlewareUnauthorized(request);')
          ..writeln('    return;')
          ..writeln('  }');
      }
      if (hasTrace) out.writeln("  $traceExpression?.add('handler');");
      out.writeln('  final result = $invocation;');
      if (depth > 0) {
        out.writeln(
          '  exitSharedSyncPipeline$depth('
          'request, $profileExpression, $traceExpression);',
        );
      }
  }
  if (hasTrace) {
    out
      ..writeln('  if ($traceExpression != null) {')
      ..writeln('    writeMiddlewareOrder(request, result, $traceExpression);')
      ..writeln('  } else {')
      ..writeln('    writeJsonStringResult(request, result);')
      ..writeln('  }');
  } else {
    out.writeln('  writeJsonStringResult(request, result);');
  }
}

void _writeAsyncPipelineCall(
  StringBuffer out,
  MiddlewareCandidate candidate,
  int depth,
  String invocation,
  MiddlewareProfile profile, {
  required String indent,
}) {
  final profileExpression = 'MiddlewareProfile.${profile.name}';
  switch (candidate) {
    case MiddlewareCandidate.phase1b:
      out.writeln(
        '${indent}executeSpecializedStringFuture(request, $invocation);',
      );
    case MiddlewareCandidate.generated:
      out.writeln(
        '${indent}executeMiddlewareAsyncResponse('
        'request, _generatedAsync${_title(profile.name)}('
        'request, id, $profileExpression));',
      );
    case MiddlewareCandidate.runtime:
      out
        ..writeln('${indent}executeMiddlewareAsyncResponse(')
        ..writeln('$indent  request,')
        ..writeln('$indent  executeRuntimeAsyncPipeline(')
        ..writeln('$indent    request,')
        ..writeln('$indent    runtimeMiddlewareSteps,')
        ..writeln('$indent    $profileExpression,')
        ..writeln('$indent    () => $invocation,')
        ..writeln('$indent  ),')
        ..writeln('$indent);');
    case MiddlewareCandidate.shared:
      out.writeln(
        '${indent}executeMiddlewareAsyncResponse('
        'request, _sharedAsyncPipeline(request, id, $profileExpression));',
      );
  }
}

void _writeSharedAsyncExecutor(StringBuffer out, int depth) {
  out
    ..writeln('Future<String?> _sharedAsyncPipeline(')
    ..writeln('  HttpRequest request,')
    ..writeln('  int id,')
    ..writeln('  MiddlewareProfile profile,')
    ..writeln(') async {')
    ..writeln(
      '  if (profile == MiddlewareProfile.asyncHandlerSyncMiddleware) {',
    );
  if (depth > 0) {
    out
      ..writeln('    if (!enterSharedSyncPipeline$depth(request, profile)) {')
      ..writeln('      return null;')
      ..writeln('    }');
  }
  out.writeln('    final result = await middlewareImmediateAsyncHandler(id);');
  if (depth > 0) {
    out.writeln('    exitSharedSyncPipeline$depth(request, profile);');
  }
  out
    ..writeln('    return result;')
    ..writeln('  }');
  if (depth > 0) {
    out
      ..writeln(
        '  if (!await enterSharedAsyncPipeline(request, $depth, profile)) {',
      )
      ..writeln('    return null;')
      ..writeln('  }');
  }
  out
    ..writeln('  final result = profile == MiddlewareProfile.mixed')
    ..writeln('      ? await middlewareBoundaryAsyncHandler(id)')
    ..writeln('      : await middlewareImmediateAsyncHandler(id);');
  if (depth > 0) {
    out.writeln('  await exitSharedAsyncPipeline(request, $depth, profile);');
  }
  out
    ..writeln('  return result;')
    ..writeln('}')
    ..writeln();
}

void _writeGeneratedAsyncExecutor(
  StringBuffer out,
  int depth,
  MiddlewareProfile profile,
) {
  final name = '_generatedAsync${_title(profile.name)}';
  out
    ..writeln('Future<String?> $name(')
    ..writeln('  HttpRequest request,')
    ..writeln('  int id,')
    ..writeln('  MiddlewareProfile profile,')
    ..writeln(') async {');
  for (var index = 0; index < depth; index++) {
    final asyncStep = _generatedAsyncStep(profile, index);
    final before = asyncStep
        ? 'await middlewareBeforeAsync(request, $index, profile)'
        : 'generatedMiddlewareBefore(request, $index, profile)';
    out
      ..writeln('  final decision$index = $before;')
      ..writeln('  if (decision$index == MiddlewareDecision.unauthorized) {');
    for (var outer = index - 1; outer >= 0; outer--) {
      final outerAsync = _generatedAsyncStep(profile, outer);
      out.writeln(
        outerAsync
            ? '    await middlewareAfterAsync(request, $outer, profile);'
            : '    generatedMiddlewareAfter(request, $outer, profile);',
      );
    }
    out
      ..writeln('    return null;')
      ..writeln('  }');
  }
  final handler = profile == MiddlewareProfile.mixed
      ? 'middlewareBoundaryAsyncHandler(id)'
      : 'middlewareImmediateAsyncHandler(id)';
  out.writeln('  final result = await $handler;');
  for (var index = depth - 1; index >= 0; index--) {
    final asyncStep = _generatedAsyncStep(profile, index);
    out.writeln(
      asyncStep
          ? '  await middlewareAfterAsync(request, $index, profile);'
          : '  generatedMiddlewareAfter(request, $index, profile);',
    );
  }
  out
    ..writeln('  return result;')
    ..writeln('}')
    ..writeln();
}

bool _generatedAsyncStep(MiddlewareProfile profile, int index) =>
    profile == MiddlewareProfile.asyncMiddleware ||
    profile == MiddlewareProfile.shortAsync ||
    (profile == MiddlewareProfile.mixed && index.isOdd) ||
    (profile == MiddlewareProfile.errorAsync && index == 0);

String _title(String value) => value[0].toUpperCase() + value.substring(1);
