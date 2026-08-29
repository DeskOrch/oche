import 'dart:convert';

import 'package:handler_execution_benchmark/handler_execution_benchmark.dart';

String generateHandlerSource(HandlerCandidate candidate, int routeCount) {
  if (routeCount != 10 && routeCount != 100 && routeCount != 1000) {
    throw ArgumentError.value(routeCount, 'routeCount');
  }
  final out = StringBuffer()
    ..writeln('// GENERATED BENCHMARK SOURCE. DO NOT EDIT.')
    ..writeln("import 'dart:io';")
    ..writeln()
    ..writeln(
      "import 'package:handler_execution_benchmark/"
      "handler_execution_benchmark.dart';",
    )
    ..writeln()
    ..writeln("const generatedCandidate = '${candidate.name}';")
    ..writeln('const generatedRouteCount = $routeCount;')
    ..writeln()
    ..writeln('Future<void> main(List<String> arguments) =>')
    ..writeln('    runHandlerBenchmarkServer(')
    ..writeln('      arguments,')
    ..writeln(
      "      name: 'handler-\$generatedCandidate-\$generatedRouteCount',",
    )
    ..writeln('      dispatch: generatedHandlerDispatch,')
    ..writeln('    );')
    ..writeln();

  _writeAdapters(out, candidate, routeCount);
  _writeDispatch(out, routeCount);
  return out.toString();
}

void _writeDispatch(StringBuffer out, int routeCount) {
  out
    ..writeln('void generatedHandlerDispatch(HttpRequest request) {')
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
    ..writeln("        case 'instance':")
    ..writeln('          final id = int.tryParse(segments[1]);')
    ..writeln('          if (id == null) {')
    ..writeln("            writeInvalidParameter(request, 'id');")
    ..writeln('            return;')
    ..writeln('          }')
    ..writeln('          _instanceRoute(request, id);')
    ..writeln('          return;')
    ..writeln("        case 'request':")
    ..writeln('          _requestRoute(request, segments[1]);')
    ..writeln('          return;')
    ..writeln("        case 'errors':")
    ..writeln('          _errorsRoute(request, segments[1]);')
    ..writeln('          return;')
    ..writeln('      }')
    ..writeln('      break;')
    ..writeln('    case 3:')
    ..writeln("      if (segments[0] == 'async') {")
    ..writeln('        final id = int.tryParse(segments[2]);')
    ..writeln('        if (id == null) {')
    ..writeln("          writeInvalidParameter(request, 'id');")
    ..writeln('          return;')
    ..writeln('        }')
    ..writeln('        _asyncRoute(request, segments[1], id);')
    ..writeln('        return;')
    ..writeln('      }');
  _writeSyntheticCases(out, routeCount, 0);
  out
    ..writeln('      break;')
    ..writeln('    case 4:')
    ..writeln("      if (segments[0] == 'orders' &&")
    ..writeln("          segments[2] == 'items') {")
    ..writeln('        final userId = int.tryParse(segments[1]);')
    ..writeln('        if (userId == null) {')
    ..writeln("          writeInvalidParameter(request, 'userId');")
    ..writeln('          return;')
    ..writeln('        }')
    ..writeln('        final orderId = int.tryParse(segments[3]);')
    ..writeln('        if (orderId == null) {')
    ..writeln("          writeInvalidParameter(request, 'orderId');")
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
  _writeSyntheticCases(out, routeCount, 1);
  out
    ..writeln('      break;')
    ..writeln('    case 6:');
  _writeSyntheticCases(out, routeCount, 2);
  out
    ..writeln('      break;')
    ..writeln('  }')
    ..writeln('  writeNotFound(request);')
    ..writeln('}');
}

void _writeSyntheticCases(StringBuffer out, int routeCount, int shape) {
  final matching = <int>[
    for (var routeIndex = 10; routeIndex < routeCount; routeIndex++)
      if ((routeIndex - 10) % 3 == shape) routeIndex,
  ];
  if (matching.isEmpty) return;
  out
    ..writeln("      if (segments[0] == 'generated') {")
    ..writeln('        switch (segments[1]) {');
  for (final routeIndex in matching) {
    final synthetic = routeIndex - 10;
    out.writeln("          case 'r$synthetic':");
    if (shape == 0) {
      out
        ..writeln("            if (segments[2] != 'literal') break;")
        ..writeln('            _syntheticRoute(request, $routeIndex);');
    } else if (shape == 1) {
      out
        ..writeln("            if (segments[2] != 'items') break;")
        ..writeln('            final id = int.tryParse(segments[3]);')
        ..writeln('            if (id == null) {')
        ..writeln("              writeInvalidParameter(request, 'id');")
        ..writeln('              return;')
        ..writeln('            }')
        ..writeln('            _syntheticRoute(request, $routeIndex, id);');
    } else {
      out
        ..writeln("            if (segments[2] != 'items' ||")
        ..writeln("                segments[4] != 'children') break;")
        ..writeln('            final id = int.tryParse(segments[3]);')
        ..writeln('            if (id == null) {')
        ..writeln("              writeInvalidParameter(request, 'id');")
        ..writeln('              return;')
        ..writeln('            }')
        ..writeln('            final childId = int.tryParse(segments[5]);')
        ..writeln('            if (childId == null) {')
        ..writeln("              writeInvalidParameter(request, 'childId');")
        ..writeln('              return;')
        ..writeln('            }')
        ..writeln(
          '            _syntheticRoute('
          'request, $routeIndex, id, childId);',
        );
    }
    out.writeln('            return;');
  }
  out
    ..writeln('        }')
    ..writeln('      }');
}

void _writeAdapters(
  StringBuffer out,
  HandlerCandidate candidate,
  int routeCount,
) {
  _writeSimpleAdapter(
    out,
    candidate,
    name: 'health',
    invocation: 'healthHandler()',
    kind: ExperimentalResultKind.text,
  );
  _writeSimpleAdapter(
    out,
    candidate,
    name: 'status',
    invocation: 'statusHandler()',
    kind: ExperimentalResultKind.jsonString,
  );
  _writePayloadAdapter(out, candidate);
  _writeUsersAdapter(out, candidate);
  _writeAsyncAdapter(out, candidate);
  _writeInstanceAdapter(out, candidate);
  _writeRequestAdapter(out, candidate);
  _writeErrorsAdapter(out, candidate);
  _writeTwoArgumentAdapter(out, candidate);
  _writeCatalogAdapter(out, candidate);
  if (routeCount > 10) _writeSyntheticAdapter(out, candidate);
}

void _writeSimpleAdapter(
  StringBuffer out,
  HandlerCandidate candidate, {
  required String name,
  required String invocation,
  required ExperimentalResultKind kind,
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
  _writeSyncResult(out, candidate, invocation, kind);
  out
    ..writeln('}')
    ..writeln();
}

void _writePayloadAdapter(StringBuffer out, HandlerCandidate candidate) {
  out
    ..writeln('void _payloadRoute(HttpRequest request) {')
    ..writeln('  switch (request.method) {')
    ..writeln("    case 'GET':");
  _writeSyncResult(
    out,
    candidate,
    'bytesHandler()',
    ExperimentalResultKind.bytes,
    indent: '      ',
  );
  out
    ..writeln('      return;')
    ..writeln("    case 'DELETE':")
    ..writeln('      voidHandler();');
  _writeSyncResult(
    out,
    candidate,
    'null',
    ExperimentalResultKind.noContent,
    indent: '      ',
  );
  out
    ..writeln('      return;')
    ..writeln("    case 'POST':");
  _writeVoidFuture(out, candidate, 'asyncVoidHandler()', indent: '      ');
  out
    ..writeln('      return;')
    ..writeln('  }')
    ..writeln(
      "  writeMethodNotAllowed(request, const ['GET', 'POST', 'DELETE']);",
    )
    ..writeln('}')
    ..writeln();
}

void _writeUsersAdapter(StringBuffer out, HandlerCandidate candidate) {
  out
    ..writeln('void _usersRoute(HttpRequest request, int id) {')
    ..writeln('  switch (request.method) {')
    ..writeln("    case 'GET':");
  _writeSyncResult(
    out,
    candidate,
    'stringIdHandler(id)',
    ExperimentalResultKind.jsonString,
    indent: '      ',
  );
  out
    ..writeln('      return;')
    ..writeln("    case 'POST':");
  _writeSyncResult(
    out,
    candidate,
    'userResultHandler(id)',
    ExperimentalResultKind.user,
    indent: '      ',
  );
  out
    ..writeln('      return;')
    ..writeln("    case 'PUT':");
  _writeFutureResult(
    out,
    candidate,
    'asyncUserResultHandler(id)',
    ExperimentalResultKind.user,
    indent: '      ',
  );
  out
    ..writeln('      return;')
    ..writeln('  }')
    ..writeln("  writeMethodNotAllowed(request, const ['GET', 'POST', 'PUT']);")
    ..writeln('}')
    ..writeln();
}

void _writeAsyncAdapter(StringBuffer out, HandlerCandidate candidate) {
  out
    ..writeln('void _asyncRoute(HttpRequest request, String kind, int id) {')
    ..writeln("  if (request.method != 'GET') {")
    ..writeln("    writeMethodNotAllowed(request, const ['GET']);")
    ..writeln('    return;')
    ..writeln('  }')
    ..writeln("  if (kind == 'immediate') {");
  _writeFutureResult(
    out,
    candidate,
    'immediateAsyncHandler(id)',
    ExperimentalResultKind.jsonString,
    indent: '    ',
  );
  out
    ..writeln('    return;')
    ..writeln('  }')
    ..writeln("  if (kind == 'boundary') {");
  _writeFutureResult(
    out,
    candidate,
    'boundaryAsyncHandler(id)',
    ExperimentalResultKind.jsonString,
    indent: '    ',
  );
  out
    ..writeln('    return;')
    ..writeln('  }')
    ..writeln('  writeNotFound(request);')
    ..writeln('}')
    ..writeln();
}

void _writeInstanceAdapter(StringBuffer out, HandlerCandidate candidate) {
  out
    ..writeln('void _instanceRoute(HttpRequest request, int id) {')
    ..writeln("  if (request.method == 'GET') {");
  _writeSyncResult(
    out,
    candidate,
    'handlerBenchmarkController.findById(id)',
    ExperimentalResultKind.user,
    indent: '    ',
  );
  out
    ..writeln('    return;')
    ..writeln('  }')
    ..writeln("  if (request.method == 'POST') {");
  _writeFutureResult(
    out,
    candidate,
    'handlerBenchmarkController.findByIdAsync(id)',
    ExperimentalResultKind.user,
    indent: '    ',
  );
  out
    ..writeln('    return;')
    ..writeln('  }')
    ..writeln("  writeMethodNotAllowed(request, const ['GET', 'POST']);")
    ..writeln('}')
    ..writeln();
}

void _writeRequestAdapter(StringBuffer out, HandlerCandidate candidate) {
  out
    ..writeln('void _requestRoute(HttpRequest request, String kind) {')
    ..writeln("  if (request.method != 'GET') {")
    ..writeln("    writeMethodNotAllowed(request, const ['GET']);")
    ..writeln('    return;')
    ..writeln('  }')
    ..writeln("  if (kind == 'raw') {");
  _writeSyncResult(
    out,
    candidate,
    'rawRequestHandler(request)',
    ExperimentalResultKind.jsonString,
    indent: '    ',
  );
  out
    ..writeln('    return;')
    ..writeln('  }')
    ..writeln("  if (kind == 'view') {");
  _writeSyncResult(
    out,
    candidate,
    'requestViewHandler(ExperimentalRequestView(request))',
    ExperimentalResultKind.jsonString,
    indent: '    ',
  );
  out
    ..writeln('    return;')
    ..writeln('  }')
    ..writeln('  writeNotFound(request);')
    ..writeln('}')
    ..writeln();
}

void _writeErrorsAdapter(StringBuffer out, HandlerCandidate candidate) {
  out
    ..writeln('void _errorsRoute(HttpRequest request, String kind) {')
    ..writeln("  if (request.method != 'GET') {")
    ..writeln("    writeMethodNotAllowed(request, const ['GET']);")
    ..writeln('    return;')
    ..writeln('  }');
  _writeSyncResult(
    out,
    candidate,
    'errorHandler(kind)',
    ExperimentalResultKind.jsonString,
  );
  out
    ..writeln('}')
    ..writeln();
}

void _writeTwoArgumentAdapter(StringBuffer out, HandlerCandidate candidate) {
  out
    ..writeln(
      'void _ordersRoute(HttpRequest request, int userId, int orderId) {',
    )
    ..writeln("  if (request.method != 'GET') {")
    ..writeln("    writeMethodNotAllowed(request, const ['GET']);")
    ..writeln('    return;')
    ..writeln('  }');
  _writeSyncResult(
    out,
    candidate,
    'twoIntHandler(userId, orderId)',
    ExperimentalResultKind.jsonString,
  );
  out
    ..writeln('}')
    ..writeln();
}

void _writeCatalogAdapter(StringBuffer out, HandlerCandidate candidate) {
  out
    ..writeln('void _catalogRoute(HttpRequest request, String sku, int id) {')
    ..writeln("  if (request.method != 'GET') {")
    ..writeln("    writeMethodNotAllowed(request, const ['GET']);")
    ..writeln('    return;')
    ..writeln('  }');
  _writeSyncResult(
    out,
    candidate,
    'stringAndIntHandler(sku, id)',
    ExperimentalResultKind.jsonString,
  );
  out
    ..writeln('}')
    ..writeln();
}

void _writeSyntheticAdapter(StringBuffer out, HandlerCandidate candidate) {
  out
    ..writeln('void _syntheticRoute(')
    ..writeln('  HttpRequest request,')
    ..writeln('  int routeId, [')
    ..writeln('  int? first,')
    ..writeln('  int? second,')
    ..writeln(']) {')
    ..writeln("  if (request.method != 'GET') {")
    ..writeln("    writeMethodNotAllowed(request, const ['GET']);")
    ..writeln('    return;')
    ..writeln('  }');
  _writeSyncResult(
    out,
    candidate,
    'syntheticHandler(routeId, first, second)',
    ExperimentalResultKind.jsonString,
  );
  out
    ..writeln('}')
    ..writeln();
}

void _writeSyncResult(
  StringBuffer out,
  HandlerCandidate candidate,
  String invocation,
  ExperimentalResultKind kind, {
  String indent = '  ',
}) {
  switch (candidate) {
    case HandlerCandidate.phase1aDirect:
      out.writeln(
        '${indent}writePhase1aResponse('
        'request, ${_phase1aMapping(invocation, kind)});',
      );
    case HandlerCandidate.specialized:
      out.writeln('$indent${_specializedWrite(invocation, kind)}');
    case HandlerCandidate.uniform:
      out.writeln(
        '${indent}executeUniformResult('
        'request, $invocation, ExperimentalResultKind.${kind.name});',
      );
  }
}

void _writeFutureResult(
  StringBuffer out,
  HandlerCandidate candidate,
  String invocation,
  ExperimentalResultKind kind, {
  required String indent,
}) {
  switch (candidate) {
    case HandlerCandidate.phase1aDirect:
      final executor = kind == ExperimentalResultKind.user
          ? 'executePhase1aUserFuture'
          : 'executePhase1aStringFuture';
      out.writeln('$indent$executor(request, $invocation);');
    case HandlerCandidate.specialized:
      final executor = kind == ExperimentalResultKind.user
          ? 'executeSpecializedUserFuture'
          : 'executeSpecializedStringFuture';
      out.writeln('$indent$executor(request, $invocation);');
    case HandlerCandidate.uniform:
      out.writeln(
        '${indent}executeUniformResult('
        'request, $invocation, ExperimentalResultKind.${kind.name});',
      );
  }
}

void _writeVoidFuture(
  StringBuffer out,
  HandlerCandidate candidate,
  String invocation, {
  required String indent,
}) {
  final executor = switch (candidate) {
    HandlerCandidate.phase1aDirect => 'executePhase1aVoidFuture',
    HandlerCandidate.specialized => 'executeSpecializedVoidFuture',
    HandlerCandidate.uniform => 'executeUniformVoidFuture',
  };
  out.writeln('$indent$executor(request, $invocation);');
}

String _phase1aMapping(String invocation, ExperimentalResultKind kind) =>
    switch (kind) {
      ExperimentalResultKind.text => 'phase1aTextResponse($invocation)',
      ExperimentalResultKind.jsonString => 'phase1aJsonResponse($invocation)',
      ExperimentalResultKind.bytes => 'phase1aBytesResponse($invocation)',
      ExperimentalResultKind.noContent => 'phase1aNoContentResponse',
      ExperimentalResultKind.user => 'phase1aUserResponse($invocation)',
    };

String _specializedWrite(String invocation, ExperimentalResultKind kind) =>
    switch (kind) {
      ExperimentalResultKind.text => 'writeTextResult(request, $invocation);',
      ExperimentalResultKind.jsonString =>
        'writeJsonStringResult(request, $invocation);',
      ExperimentalResultKind.bytes => 'writeBytesResult(request, $invocation);',
      ExperimentalResultKind.noContent => 'writeNoContentResult(request);',
      ExperimentalResultKind.user => 'writeUserResult(request, $invocation);',
    };

String handlerImplementationName(HandlerCandidate candidate) =>
    switch (candidate) {
      HandlerCandidate.phase1aDirect => 'handler_phase1a_direct',
      HandlerCandidate.specialized => 'handler_specialized',
      HandlerCandidate.uniform => 'handler_uniform',
    };

String handlerSourceStem(HandlerCandidate candidate) => switch (candidate) {
  HandlerCandidate.phase1aDirect => 'phase1a_direct',
  HandlerCandidate.specialized => 'specialized',
  HandlerCandidate.uniform => 'uniform',
};

String quoted(String value) => jsonEncode(value);
