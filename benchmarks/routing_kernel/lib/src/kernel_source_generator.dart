import 'dart:convert';

import 'package:routing_kernel_benchmark/src/kernel_route_model.dart';

enum KernelCandidate { tree, indexed }

String generateKernelSource(KernelCandidate candidate, int routeCount) {
  if (routeCount != 10 && routeCount != 100 && routeCount != 1000) {
    throw ArgumentError.value(routeCount, 'routeCount');
  }
  final out = StringBuffer()
    ..writeln('// GENERATED BENCHMARK SOURCE. DO NOT EDIT.')
    ..writeln('// ignore_for_file: curly_braces_in_flow_control_structures')
    ..writeln("import 'dart:io';")
    ..writeln()
    ..writeln(
      "import 'package:routing_kernel_benchmark/"
      "routing_kernel_benchmark.dart';",
    )
    ..writeln()
    ..writeln("const generatedCandidate = '${candidate.name}';")
    ..writeln('const generatedRouteCount = $routeCount;')
    ..writeln()
    ..writeln('Future<void> main(List<String> arguments) {')
    ..writeln("  if (arguments.contains('--lookup')) {")
    ..writeln('    return runKernelLookupBenchmark(')
    ..writeln('      arguments,')
    ..writeln('      candidate: generatedCandidate,')
    ..writeln('      routeCount: generatedRouteCount,')
    ..writeln('      dispatch: generatedKernelDispatch,')
    ..writeln('    );')
    ..writeln('  }')
    ..writeln('  return runKernelBenchmarkServer(')
    ..writeln('    arguments,')
    ..writeln("    name: '\$generatedCandidate-\$generatedRouteCount',")
    ..writeln('    dispatch: generatedKernelDispatch,')
    ..writeln('  );')
    ..writeln('}')
    ..writeln()
    ..writeln('KernelResponse generatedKernelDispatch(')
    ..writeln('  String method,')
    ..writeln('  Uri uri,')
    ..writeln('  HttpRequest? request,')
    ..writeln(') {')
    ..writeln('  final segments = kernelPathSegments(uri);')
    ..writeln('  if (segments == null) return notFoundResponse;');

  if (candidate == KernelCandidate.tree) {
    _writeTreeDispatch(out, routeCount);
  } else {
    _writeIndexedDispatch(out, routeCount);
  }
  out
    ..writeln('  return notFoundResponse;')
    ..writeln('}');
  return out.toString();
}

void _writeTreeDispatch(StringBuffer out, int routeCount) {
  out
    ..writeln('  switch (segments.length) {')
    ..writeln('    case 1:')
    ..writeln('      switch (segments[0]) {')
    ..writeln("        case 'health':")
    ..writeln("          return method == 'GET'")
    ..writeln('              ? healthHandler(request)')
    ..writeln("              : methodNotAllowedResponse(const ['GET']);")
    ..writeln("        case 'users':")
    ..writeln('          return switch (method) {')
    ..writeln("            'GET' => usersHandler(request),")
    ..writeln("            'POST' => createUserHandler(request),")
    ..writeln(
      "            _ => methodNotAllowedResponse(const ['GET', 'POST']),",
    )
    ..writeln('          };')
    ..writeln("        case 'products':")
    ..writeln("          return method == 'GET'")
    ..writeln('              ? productsHandler(request)')
    ..writeln("              : methodNotAllowedResponse(const ['GET']);")
    ..writeln('      }')
    ..writeln('      break;')
    ..writeln('    case 2:')
    ..writeln("      if (segments[0] == 'users') {")
    ..writeln("        if (segments[1] == 'search') {")
    ..writeln("          return method == 'GET'")
    ..writeln('              ? searchUsersHandler(request)')
    ..writeln("              : methodNotAllowedResponse(const ['GET']);")
    ..writeln('        }')
    ..writeln("        if (method != 'GET' && method != 'DELETE') {")
    ..writeln(
      "          return methodNotAllowedResponse(const ['GET', 'DELETE']);",
    )
    ..writeln('        }')
    ..writeln('        final id = int.tryParse(segments[1]);')
    ..writeln("        if (id == null) return invalidParameterResponse('id');")
    ..writeln("        return method == 'GET'")
    ..writeln('            ? userByIdHandler(request, id)')
    ..writeln('            : deleteUserHandler(request, id);')
    ..writeln('      }')
    ..writeln("      if (segments[0] == 'products') {")
    ..writeln('        return switch (method) {')
    ..writeln("          'GET' => productBySkuHandler(request, segments[1]),")
    ..writeln("          'PUT' => updateProductHandler(request, segments[1]),")
    ..writeln("          'PATCH' => patchProductHandler(request, segments[1]),")
    ..writeln('          _ => methodNotAllowedResponse(')
    ..writeln("            const ['GET', 'PUT', 'PATCH'],")
    ..writeln('          ),')
    ..writeln('        };')
    ..writeln('      }')
    ..writeln("      if (segments[0] == 'errors') {")
    ..writeln("        return method == 'GET'")
    ..writeln('            ? errorHandler(request, segments[1])')
    ..writeln("            : methodNotAllowedResponse(const ['GET']);")
    ..writeln('      }')
    ..writeln('      break;')
    ..writeln('    case 3:')
    ..writeln("      if (segments[0] == 'users' && segments[2] == 'orders') {")
    ..writeln("        if (method != 'GET') {")
    ..writeln("          return methodNotAllowedResponse(const ['GET']);")
    ..writeln('        }')
    ..writeln('        final userId = int.tryParse(segments[1]);')
    ..writeln(
      "        if (userId == null) return invalidParameterResponse('userId');",
    )
    ..writeln('        return userOrdersHandler(request, userId);')
    ..writeln('      }')
    ..writeln("      if (segments[0] == 'api' &&")
    ..writeln("          segments[1] == 'v1' &&")
    ..writeln("          segments[2] == 'status') {")
    ..writeln("        return method == 'GET'")
    ..writeln('            ? statusHandler(request)')
    ..writeln("            : methodNotAllowedResponse(const ['GET']);")
    ..writeln('      }');
  _writeTreeSyntheticCases(out, routeCount, 0);
  out
    ..writeln('      break;')
    ..writeln('    case 4:')
    ..writeln("      if (segments[0] == 'users' && segments[2] == 'orders') {")
    ..writeln("        if (method != 'GET') {")
    ..writeln("          return methodNotAllowedResponse(const ['GET']);")
    ..writeln('        }')
    ..writeln('        final userId = int.tryParse(segments[1]);')
    ..writeln(
      "        if (userId == null) return invalidParameterResponse('userId');",
    )
    ..writeln('        final orderId = int.tryParse(segments[3]);')
    ..writeln(
      "        if (orderId == null) return invalidParameterResponse('orderId');",
    )
    ..writeln('        return userOrderHandler(request, userId, orderId);')
    ..writeln('      }');
  _writeTreeSyntheticCases(out, routeCount, 1);
  out
    ..writeln('      break;')
    ..writeln('    case 6:');
  _writeTreeSyntheticCases(out, routeCount, 2);
  out
    ..writeln('      break;')
    ..writeln('  }')
    ..writeln();
}

void _writeTreeSyntheticCases(StringBuffer out, int routeCount, int shape) {
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
        ..writeln("            if (segments[2] != 'literal') {")
        ..writeln('              return notFoundResponse;')
        ..writeln('            }');
    } else if (shape == 1) {
      out
        ..writeln("            if (segments[2] != 'items') {")
        ..writeln('              return notFoundResponse;')
        ..writeln('            }');
    } else {
      out
        ..writeln("            if (segments[2] != 'items' ||")
        ..writeln("                segments[4] != 'children') {")
        ..writeln('              return notFoundResponse;')
        ..writeln('            }');
    }
    out
      ..writeln("            if (method != 'GET') {")
      ..writeln("              return methodNotAllowedResponse(const ['GET']);")
      ..writeln('            }');
    if (shape == 0) {
      out.writeln('            return syntheticHandler(request, $routeIndex);');
    } else if (shape == 1) {
      out
        ..writeln('            final id = int.tryParse(segments[3]);')
        ..writeln(
          "            if (id == null) return invalidParameterResponse('id');",
        )
        ..writeln(
          '            return syntheticHandler(request, $routeIndex, id);',
        );
    } else {
      out
        ..writeln('            final id = int.tryParse(segments[3]);')
        ..writeln(
          "            if (id == null) return invalidParameterResponse('id');",
        )
        ..writeln('            final childId = int.tryParse(segments[5]);')
        ..writeln(
          "            if (childId == null) return invalidParameterResponse('childId');",
        )
        ..writeln(
          '            return syntheticHandler('
          'request, $routeIndex, id, childId);',
        );
    }
  }
  out
    ..writeln('        }')
    ..writeln('      }');
}

void _writeIndexedDispatch(StringBuffer out, int routeCount) {
  out
    ..writeln('  switch (segments.length) {')
    ..writeln('    case 1:')
    ..writeln('      switch (kernelHash1(segments[0])) {');
  _writeHashCase(
    out,
    ['health'],
    "return method == 'GET' ? healthHandler(request) : "
    "methodNotAllowedResponse(const ['GET']);",
  );
  _writeHashCase(
    out,
    ['users'],
    "return switch (method) { 'GET' => usersHandler(request), "
    "'POST' => createUserHandler(request), _ => "
    "methodNotAllowedResponse(const ['GET', 'POST']) };",
  );
  _writeHashCase(
    out,
    ['products'],
    "return method == 'GET' ? productsHandler(request) : "
    "methodNotAllowedResponse(const ['GET']);",
  );
  out
    ..writeln('      }')
    ..writeln('      break;')
    ..writeln('    case 2:')
    ..writeln('      switch (kernelHash2(segments[0], segments[1])) {');
  _writeHashCase(
    out,
    ['users', 'search'],
    "return method == 'GET' ? searchUsersHandler(request) : "
    "methodNotAllowedResponse(const ['GET']);",
  );
  out
    ..writeln('      }')
    ..writeln('      switch (kernelHash1(segments[0])) {');
  _writeHashCase(
    out,
    ['users'],
    "if (method != 'GET' && method != 'DELETE') return "
    "methodNotAllowedResponse(const ['GET', 'DELETE']); "
    "final id = int.tryParse(segments[1]); "
    "if (id == null) return invalidParameterResponse('id'); "
    "return method == 'GET' ? userByIdHandler(request, id) : "
    'deleteUserHandler(request, id);',
  );
  _writeHashCase(
    out,
    ['products'],
    "return switch (method) { 'GET' => productBySkuHandler(request, "
    "segments[1]), 'PUT' => updateProductHandler(request, segments[1]), "
    "'PATCH' => patchProductHandler(request, segments[1]), _ => "
    "methodNotAllowedResponse(const ['GET', 'PUT', 'PATCH']) };",
  );
  _writeHashCase(
    out,
    ['errors'],
    "return method == 'GET' ? errorHandler(request, segments[1]) : "
    "methodNotAllowedResponse(const ['GET']);",
  );
  out
    ..writeln('      }')
    ..writeln('      break;')
    ..writeln('    case 3:')
    ..writeln('      switch (kernelHash3(')
    ..writeln('        segments[0], segments[1], segments[2],')
    ..writeln('      )) {');
  _writeHashCase(
    out,
    ['api', 'v1', 'status'],
    "return method == 'GET' ? statusHandler(request) : "
    "methodNotAllowedResponse(const ['GET']);",
  );
  for (var routeIndex = 10; routeIndex < routeCount; routeIndex += 3) {
    final synthetic = routeIndex - 10;
    _writeHashCase(
      out,
      ['generated', 'r$synthetic', 'literal'],
      "return method == 'GET' ? syntheticHandler(request, $routeIndex) : "
      "methodNotAllowedResponse(const ['GET']);",
    );
  }
  out
    ..writeln('      }')
    ..writeln('      switch (kernelHash2(segments[0], segments[2])) {');
  _writeHashCase(
    out,
    ['users', 'orders'],
    "if (method != 'GET') return methodNotAllowedResponse(const ['GET']); "
    'final userId = int.tryParse(segments[1]); '
    "if (userId == null) return invalidParameterResponse('userId'); "
    'return userOrdersHandler(request, userId);',
    positions: const [0, 2],
  );
  out
    ..writeln('      }')
    ..writeln('      break;')
    ..writeln('    case 4:')
    ..writeln('      switch (kernelHash2(segments[0], segments[2])) {');
  _writeHashCase(
    out,
    ['users', 'orders'],
    "if (method != 'GET') return methodNotAllowedResponse(const ['GET']); "
    'final userId = int.tryParse(segments[1]); '
    "if (userId == null) return invalidParameterResponse('userId'); "
    'final orderId = int.tryParse(segments[3]); '
    "if (orderId == null) return invalidParameterResponse('orderId'); "
    'return userOrderHandler(request, userId, orderId);',
    positions: const [0, 2],
  );
  out
    ..writeln('      }')
    ..writeln('      switch (kernelHash3(')
    ..writeln('        segments[0], segments[1], segments[2],')
    ..writeln('      )) {');
  for (var routeIndex = 11; routeIndex < routeCount; routeIndex += 3) {
    final synthetic = routeIndex - 10;
    _writeHashCase(
      out,
      ['generated', 'r$synthetic', 'items'],
      "if (method != 'GET') return methodNotAllowedResponse(const ['GET']); "
      'final id = int.tryParse(segments[3]); '
      "if (id == null) return invalidParameterResponse('id'); "
      'return syntheticHandler(request, $routeIndex, id);',
    );
  }
  out
    ..writeln('      }')
    ..writeln('      break;')
    ..writeln('    case 6:')
    ..writeln('      switch (kernelHash4(')
    ..writeln('        segments[0], segments[1], segments[2], segments[4],')
    ..writeln('      )) {');
  for (var routeIndex = 12; routeIndex < routeCount; routeIndex += 3) {
    final synthetic = routeIndex - 10;
    _writeHashCase(
      out,
      ['generated', 'r$synthetic', 'items', 'children'],
      "if (method != 'GET') return methodNotAllowedResponse(const ['GET']); "
      'final id = int.tryParse(segments[3]); '
      "if (id == null) return invalidParameterResponse('id'); "
      'final childId = int.tryParse(segments[5]); '
      "if (childId == null) return invalidParameterResponse('childId'); "
      'return syntheticHandler(request, $routeIndex, id, childId);',
      positions: const [0, 1, 2, 4],
    );
  }
  out
    ..writeln('      }')
    ..writeln('      break;')
    ..writeln('  }')
    ..writeln();
}

void _writeHashCase(
  StringBuffer out,
  List<String> literals,
  String action, {
  List<int>? positions,
}) {
  final hash = generatedKernelHash(literals);
  final segmentPositions =
      positions ?? List.generate(literals.length, (i) => i);
  if (segmentPositions.length != literals.length) {
    throw ArgumentError('Hash literals and positions must have equal lengths.');
  }
  final checks = [
    for (var index = 0; index < literals.length; index++)
      'segments[${segmentPositions[index]}] == ${jsonEncode(literals[index])}',
  ].join(' && ');
  out
    ..writeln('        case $hash:')
    ..writeln('          if ($checks) {')
    ..writeln('            $action')
    ..writeln('          }')
    ..writeln('          break;');
}
