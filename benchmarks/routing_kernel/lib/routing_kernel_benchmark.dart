/// Internal HTTP contract shared by the Phase 1A routing-kernel candidates.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:routing_kernel_benchmark/src/kernel_route_model.dart';

typedef KernelDispatch = KernelResponse Function(
  String method,
  Uri uri,
  HttpRequest? request,
);

final class KernelResponse {
  const KernelResponse({
    required this.statusCode,
    required this.contentType,
    required this.body,
    this.allow = const [],
  });

  final int statusCode;
  final String contentType;
  final String body;
  final List<String> allow;
}

final class ExpectedKernelException implements Exception {
  const ExpectedKernelException(this.internalMessage);

  final String internalMessage;
}

const _jsonType = 'application/json; charset=utf-8';
const _textType = 'text/plain; charset=utf-8';

const notFoundResponse = KernelResponse(
  statusCode: HttpStatus.notFound,
  contentType: _textType,
  body: 'Not Found',
);

const internalErrorResponse = KernelResponse(
  statusCode: HttpStatus.internalServerError,
  contentType: _jsonType,
  body: '{"error":"internal server error"}',
);

const expectedErrorResponse = KernelResponse(
  statusCode: HttpStatus.conflict,
  contentType: _jsonType,
  body: '{"error":"expected failure"}',
);

KernelResponse methodNotAllowedResponse(List<String> methods) => KernelResponse(
  statusCode: HttpStatus.methodNotAllowed,
  contentType: _textType,
  body: 'Method Not Allowed',
  allow: methods,
);

KernelResponse invalidParameterResponse(String name) => KernelResponse(
  statusCode: HttpStatus.badRequest,
  contentType: _jsonType,
  body: '{"error":"$name must be an integer"}',
);

/// Applies only error-to-response behavior; dispatch remains generated code.
KernelResponse executeKernelDispatch(
  KernelDispatch dispatch,
  String method,
  Uri uri, [
  HttpRequest? request,
]) {
  try {
    return dispatch(method, uri, request);
  } on ExpectedKernelException {
    return expectedErrorResponse;
  } on Object {
    return internalErrorResponse;
  }
}

Future<HttpServer> startKernelBenchmarkServer(
  KernelDispatch dispatch, {
  InternetAddress? address,
  int port = 8080,
}) async {
  final server = await HttpServer.bind(
    address ?? InternetAddress.loopbackIPv4,
    port,
  );
  server.autoCompress = false;
  server.listen((request) {
    final result = executeKernelDispatch(
      dispatch,
      request.method,
      request.uri,
      request,
    );
    final bodyBytes = utf8.encode(result.body);
    request.response
      ..statusCode = result.statusCode
      ..headers.contentType = ContentType.parse(result.contentType)
      ..contentLength = bodyBytes.length;
    if (result.allow.isNotEmpty) {
      request.response.headers.set(
        HttpHeaders.allowHeader,
        result.allow.join(', '),
      );
    }
    request.response.add(bodyBytes);
    unawaited(request.response.close());
  });
  return server;
}

Future<void> runKernelBenchmarkServer(
  List<String> arguments, {
  required String name,
  required KernelDispatch dispatch,
}) async {
  final options = _KernelServerOptions.parse(arguments);
  final addresses = await InternetAddress.lookup(options.host);
  if (addresses.isEmpty) throw StateError('Could not resolve ${options.host}.');
  final server = await startKernelBenchmarkServer(
    dispatch,
    address: addresses.first,
    port: options.port,
  );
  stdout.writeln('$name ready on ${options.host}:${server.port}');

  final stopped = Completer<void>();
  final subscriptions = <StreamSubscription<ProcessSignal>>[];
  Future<void> stop(ProcessSignal signal) async {
    if (stopped.isCompleted) return;
    await server.close();
    stopped.complete();
  }

  subscriptions.add(ProcessSignal.sigint.watch().listen(stop));
  if (!Platform.isWindows) {
    subscriptions.add(ProcessSignal.sigterm.watch().listen(stop));
  }
  await stopped.future;
  for (final subscription in subscriptions) {
    await subscription.cancel();
  }
}

Future<void> runKernelLookupBenchmark(
  List<String> arguments, {
  required String candidate,
  required int routeCount,
  required KernelDispatch dispatch,
}) async {
  final options = _LookupOptions.parse(arguments);
  final queries = generateKernelQueries(routeCount);
  _executeKernelLookups(dispatch, queries, options.warmupLookups);
  final trials = <Map<String, Object>>[];
  for (var iteration = 1; iteration <= options.iterations; iteration++) {
    final watch = Stopwatch()..start();
    final checksum = _executeKernelLookups(
      dispatch,
      queries,
      options.lookups,
      offset: iteration * 17,
    );
    watch.stop();
    final seconds = watch.elapsedTicks / watch.frequency;
    trials.add({
      'iteration': iteration,
      'lookups': options.lookups,
      'elapsedMicroseconds': watch.elapsedMicroseconds,
      'lookupsPerSecond': options.lookups / seconds,
      'nanosecondsPerLookup': seconds * 1000000000 / options.lookups,
      'checksum': checksum,
    });
  }
  final source = options.sourcePath == null ? null : File(options.sourcePath!);
  final result = <String, Object>{
    'schemaVersion': 1,
    'kind': 'oche-routing-kernel-lookup',
    'timestampUtc': DateTime.now().toUtc().toIso8601String(),
    'candidate': candidate,
    'routeCount': routeCount,
    'queryCount': queries.length,
    'hitRatio': 0.9,
    'runtime': Platform.version,
    'binarySizeBytes': File(Platform.resolvedExecutable).lengthSync(),
    if (source != null && source.existsSync()) ...{
      'generatedSourceBytes': source.lengthSync(),
      'generatedSourceLines': source.readAsLinesSync().length,
    },
    'configuration': {
      'lookups': options.lookups,
      'warmupLookups': options.warmupLookups,
      'iterations': options.iterations,
    },
    'trials': trials,
    'aggregate': {
      'lookupsPerSecond': _summarize(
        trials.map((trial) => trial['lookupsPerSecond']! as double),
      ),
      'nanosecondsPerLookup': _summarize(
        trials.map((trial) => trial['nanosecondsPerLookup']! as double),
      ),
    },
  };
  final encoded = const JsonEncoder.withIndent('  ').convert(result);
  if (options.outputPath case final path?) {
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString('$encoded\n');
    stdout.writeln('Wrote kernel lookup results to ${file.path}');
  } else {
    stdout.writeln(encoded);
  }
}

Map<String, double> _summarize(Iterable<double> input) {
  final values = input.toList()..sort();
  final middle = values.length ~/ 2;
  final median = values.length.isOdd
      ? values[middle]
      : (values[middle - 1] + values[middle]) / 2;
  final mean = values.reduce((left, right) => left + right) / values.length;
  var squaredDifferenceSum = 0.0;
  for (final value in values) {
    final difference = value - mean;
    squaredDifferenceSum += difference * difference;
  }
  return {
    'median': median,
    'minimum': values.first,
    'maximum': values.last,
    'standardDeviation': sqrt(squaredDifferenceSum / values.length),
  };
}

int _executeKernelLookups(
  KernelDispatch dispatch,
  List<KernelQuery> queries,
  int lookups, {
  int offset = 0,
}) {
  var checksum = 0;
  for (var index = 0; index < lookups; index++) {
    final query = queries[(index + offset) & 1023];
    final result = executeKernelDispatch(dispatch, query.method, query.uri);
    checksum = (checksum + result.statusCode + result.body.length) & 0x7fffffff;
  }
  return checksum;
}

/// Returns decoded, security-checked segments or `null` for a rejected path.
///
/// Query strings are already separate in [Uri]. Trailing and duplicate slashes
/// are deliberately not normalized. Dart owns percent decoding; decoded slash,
/// backslash, NUL, and dot segments are rejected before route matching.
List<String>? kernelPathSegments(Uri uri) {
  final path = uri.path;
  if (path != '/' && path.endsWith('/')) return null;
  if (path.contains('//')) return null;
  final segments = uri.pathSegments;
  for (final segment in segments) {
    if (segment.isEmpty ||
        segment == '.' ||
        segment == '..' ||
        segment.contains('/') ||
        segment.contains(r'\') ||
        segment.contains('\u0000')) {
      return null;
    }
  }
  return segments;
}

const _healthResponse = KernelResponse(
  statusCode: HttpStatus.ok,
  contentType: _textType,
  body: 'OK',
);
const _usersResponse = KernelResponse(
  statusCode: HttpStatus.ok,
  contentType: _jsonType,
  body: '{"users":[]}',
);
const _createdUserResponse = KernelResponse(
  statusCode: HttpStatus.created,
  contentType: _jsonType,
  body: '{"created":true}',
);
const _searchResponse = KernelResponse(
  statusCode: HttpStatus.ok,
  contentType: _jsonType,
  body: '{"users":[],"query":"search"}',
);
const _productsResponse = KernelResponse(
  statusCode: HttpStatus.ok,
  contentType: _jsonType,
  body: '{"products":[]}',
);
const _statusResponse = KernelResponse(
  statusCode: HttpStatus.ok,
  contentType: _jsonType,
  body: '{"status":"ok"}',
);
const _deletedResponse = KernelResponse(
  statusCode: HttpStatus.noContent,
  contentType: _textType,
  body: '',
);

KernelResponse healthHandler(HttpRequest? request) => _healthResponse;

KernelResponse usersHandler(HttpRequest? request) => _usersResponse;

KernelResponse createUserHandler(HttpRequest? request) => _createdUserResponse;

KernelResponse searchUsersHandler(HttpRequest? request) => _searchResponse;

KernelResponse userByIdHandler(HttpRequest? request, int id) => KernelResponse(
  statusCode: HttpStatus.ok,
  contentType: _jsonType,
  body: '{"id":$id}',
);

KernelResponse deleteUserHandler(HttpRequest? request, int id) =>
    _deletedResponse;

KernelResponse userOrdersHandler(HttpRequest? request, int userId) =>
    KernelResponse(
      statusCode: HttpStatus.ok,
      contentType: _jsonType,
      body: '{"userId":$userId,"orders":[]}',
    );

KernelResponse userOrderHandler(
  HttpRequest? request,
  int userId,
  int orderId,
) => KernelResponse(
  statusCode: HttpStatus.ok,
  contentType: _jsonType,
  body: '{"userId":$userId,"orderId":$orderId}',
);

KernelResponse productsHandler(HttpRequest? request) => _productsResponse;

KernelResponse productBySkuHandler(HttpRequest? request, String sku) =>
    KernelResponse(
      statusCode: HttpStatus.ok,
      contentType: _jsonType,
      body: '{"sku":${jsonEncode(sku)}}',
    );

KernelResponse updateProductHandler(HttpRequest? request, String sku) =>
    KernelResponse(
      statusCode: HttpStatus.ok,
      contentType: _jsonType,
      body: '{"sku":${jsonEncode(sku)},"updated":true}',
    );

KernelResponse patchProductHandler(HttpRequest? request, String sku) =>
    KernelResponse(
      statusCode: HttpStatus.ok,
      contentType: _jsonType,
      body: '{"sku":${jsonEncode(sku)},"patched":true}',
    );

KernelResponse statusHandler(HttpRequest? request) => _statusResponse;

KernelResponse errorHandler(HttpRequest? request, String kind) {
  if (kind == 'expected') {
    throw const ExpectedKernelException('sensitive expected detail');
  }
  if (kind == 'unexpected') {
    throw StateError('sensitive unexpected detail');
  }
  return const KernelResponse(
    statusCode: HttpStatus.ok,
    contentType: _jsonType,
    body: '{"error":false}',
  );
}

KernelResponse syntheticHandler(
  HttpRequest? request,
  int routeId, [
  int? first,
  int? second,
]) => KernelResponse(
  statusCode: HttpStatus.ok,
  contentType: _jsonType,
  body:
      '{"route":$routeId,"first":${first ?? -1},'
      '"second":${second ?? -1}}',
);

/// Hand-written lower-bound dispatcher for the ten semantic path templates.
KernelResponse rawKernelDispatch(String method, Uri uri, HttpRequest? request) {
  final segments = kernelPathSegments(uri);
  if (segments == null) return notFoundResponse;

  if (segments.length == 1 && segments[0] == 'health') {
    return method == 'GET'
        ? healthHandler(request)
        : methodNotAllowedResponse(const ['GET']);
  }
  if (segments.isNotEmpty && segments[0] == 'users') {
    if (segments.length == 1) {
      return switch (method) {
        'GET' => usersHandler(request),
        'POST' => createUserHandler(request),
        _ => methodNotAllowedResponse(const ['GET', 'POST']),
      };
    }
    if (segments.length == 2 && segments[1] == 'search') {
      return method == 'GET'
          ? searchUsersHandler(request)
          : methodNotAllowedResponse(const ['GET']);
    }
    if (segments.length == 2) {
      if (method != 'GET' && method != 'DELETE') {
        return methodNotAllowedResponse(const ['GET', 'DELETE']);
      }
      final id = int.tryParse(segments[1]);
      if (id == null) return invalidParameterResponse('id');
      return method == 'GET'
          ? userByIdHandler(request, id)
          : deleteUserHandler(request, id);
    }
    if (segments.length >= 3 && segments[2] == 'orders') {
      if (segments.length == 3) {
        if (method != 'GET') {
          return methodNotAllowedResponse(const ['GET']);
        }
        final userId = int.tryParse(segments[1]);
        if (userId == null) return invalidParameterResponse('userId');
        return userOrdersHandler(request, userId);
      }
      if (segments.length == 4) {
        if (method != 'GET') {
          return methodNotAllowedResponse(const ['GET']);
        }
        final userId = int.tryParse(segments[1]);
        if (userId == null) return invalidParameterResponse('userId');
        final orderId = int.tryParse(segments[3]);
        if (orderId == null) return invalidParameterResponse('orderId');
        return userOrderHandler(request, userId, orderId);
      }
    }
    return notFoundResponse;
  }
  if (segments.isNotEmpty && segments[0] == 'products') {
    if (segments.length == 1) {
      return method == 'GET'
          ? productsHandler(request)
          : methodNotAllowedResponse(const ['GET']);
    }
    if (segments.length == 2) {
      return switch (method) {
        'GET' => productBySkuHandler(request, segments[1]),
        'PUT' => updateProductHandler(request, segments[1]),
        'PATCH' => patchProductHandler(request, segments[1]),
        _ => methodNotAllowedResponse(const ['GET', 'PUT', 'PATCH']),
      };
    }
    return notFoundResponse;
  }
  if (segments.length == 3 &&
      segments[0] == 'api' &&
      segments[1] == 'v1' &&
      segments[2] == 'status') {
    return method == 'GET'
        ? statusHandler(request)
        : methodNotAllowedResponse(const ['GET']);
  }
  if (segments.length == 2 && segments[0] == 'errors') {
    return method == 'GET'
        ? errorHandler(request, segments[1])
        : methodNotAllowedResponse(const ['GET']);
  }
  return notFoundResponse;
}

int kernelHash1(String a) => _hashValue(_kernelHashSeed, a);

int kernelHash2(String a, String b) =>
    _hashValue(_hashValue(_kernelHashSeed, a), b);

int kernelHash3(String a, String b, String c) =>
    _hashValue(_hashValue(_hashValue(_kernelHashSeed, a), b), c);

int kernelHash4(String a, String b, String c, String d) =>
    _hashValue(_hashValue(_hashValue(_hashValue(_kernelHashSeed, a), b), c), d);

int kernelHash5(String a, String b, String c, String d, String e) => _hashValue(
  _hashValue(_hashValue(_hashValue(_hashValue(_kernelHashSeed, a), b), c), d),
  e,
);

const _kernelHashSeed = 0x811c9dc5;

int _hashValue(int hash, String value) {
  for (final codeUnit in value.codeUnits) {
    hash = ((hash ^ codeUnit) * 0x01000193) & 0x7fffffff;
  }
  return ((hash ^ 0xff) * 0x01000193) & 0x7fffffff;
}

final class _KernelServerOptions {
  const _KernelServerOptions({required this.host, required this.port});

  final String host;
  final int port;

  static _KernelServerOptions parse(List<String> arguments) {
    var host = '127.0.0.1';
    var port = 8080;
    for (var index = 0; index < arguments.length; index++) {
      final argument = arguments[index];
      if (argument == '--host' && index + 1 < arguments.length) {
        host = arguments[++index];
      } else if (argument.startsWith('--host=')) {
        host = argument.substring('--host='.length);
      } else if (argument == '--port' && index + 1 < arguments.length) {
        port = int.parse(arguments[++index]);
      } else if (argument.startsWith('--port=')) {
        port = int.parse(argument.substring('--port='.length));
      } else {
        throw FormatException('Unknown or incomplete argument: $argument');
      }
    }
    if (port < 0 || port > 65535) {
      throw RangeError.range(port, 0, 65535, 'port');
    }
    return _KernelServerOptions(host: host, port: port);
  }
}

final class _LookupOptions {
  const _LookupOptions({
    required this.lookups,
    required this.warmupLookups,
    required this.iterations,
    required this.outputPath,
    required this.sourcePath,
  });

  final int lookups;
  final int warmupLookups;
  final int iterations;
  final String? outputPath;
  final String? sourcePath;

  static _LookupOptions parse(List<String> arguments) {
    final values = <String, String>{};
    for (var index = 0; index < arguments.length; index++) {
      final argument = arguments[index];
      if (argument == '--lookup') continue;
      if (!argument.startsWith('--')) {
        throw FormatException('Expected an option, got: $argument');
      }
      final equals = argument.indexOf('=');
      if (equals >= 0) {
        values[argument.substring(2, equals)] = argument.substring(equals + 1);
      } else if (index + 1 < arguments.length) {
        values[argument.substring(2)] = arguments[++index];
      } else {
        throw FormatException('Missing value for $argument.');
      }
    }
    const known = {
      'lookups',
      'warmup-lookups',
      'iterations',
      'output',
      'source',
    };
    final unknown = values.keys.where((key) => !known.contains(key)).toList();
    if (unknown.isNotEmpty) {
      throw FormatException('Unknown options: ${unknown.join(', ')}');
    }
    final lookups = int.parse(values['lookups'] ?? '1000000');
    final warmup = int.parse(values['warmup-lookups'] ?? '100000');
    final iterations = int.parse(values['iterations'] ?? '5');
    if (lookups < 1 || warmup < 0 || iterations < 1) {
      throw RangeError('lookups and iterations must be positive; warmup >= 0.');
    }
    return _LookupOptions(
      lookups: lookups,
      warmupLookups: warmup,
      iterations: iterations,
      outputPath: values['output'],
      sourcePath: values['source'],
    );
  }
}
