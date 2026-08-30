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
        ..writeln("            if (segments[2] != 'literal') break;")
        ..writeln('            _syntheticRoute$route(request);');
    } else if (shape == 1) {
      out
        ..writeln("            if (segments[2] != 'items') break;")
        ..writeln('            final id = int.tryParse(segments[3]);')
        ..writeln('            if (id == null) {')
        ..writeln("              writeInvalidParameter(request, 'id');")
        ..writeln('              return;')
        ..writeln('            }')
        ..writeln('            _syntheticRoute$route(request, id);');
    } else {
      out
        ..writeln("            if (segments[2] != 'items' ||")
        ..writeln("                segments[4] != 'children') break;")
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
  _writeAsyncRoute(out, candidate);
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

void _writeAsyncRoute(StringBuffer out, MiddlewareCandidate candidate) {
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
    )
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
  _writeSyncPipeline(
    out,
    candidate,
    depth,
    'invocation()',
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
  }
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
