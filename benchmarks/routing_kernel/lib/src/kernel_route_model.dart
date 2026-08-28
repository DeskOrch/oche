import 'dart:core';

final class KernelQuery {
  const KernelQuery(this.method, this.uri);

  final String method;
  final Uri uri;
}

List<KernelQuery> generateKernelQueries(int routeCount) {
  if (routeCount < 10) throw RangeError.range(routeCount, 10, null);
  return List.generate(1024, (index) {
    if (index % 10 == 0) {
      return KernelQuery('GET', Uri(path: '/missing/route$index'));
    }
    return kernelQueryForRoute((index * 31) % routeCount);
  }, growable: false);
}

KernelQuery kernelQueryForRoute(int routeIndex) {
  if (routeIndex < 0) throw RangeError.range(routeIndex, 0, null);
  return switch (routeIndex) {
    0 => KernelQuery('GET', Uri(path: '/health')),
    1 => KernelQuery('GET', Uri(path: '/users')),
    2 => KernelQuery('GET', Uri(path: '/users/search')),
    3 => KernelQuery('GET', Uri(path: '/users/42')),
    4 => KernelQuery('GET', Uri(path: '/users/42/orders')),
    5 => KernelQuery('GET', Uri(path: '/users/42/orders/91')),
    6 => KernelQuery('GET', Uri(path: '/products')),
    7 => KernelQuery('GET', Uri(path: '/products/sku-42')),
    8 => KernelQuery('GET', Uri(path: '/api/v1/status')),
    9 => KernelQuery('GET', Uri(path: '/errors/none')),
    _ => _syntheticQuery(routeIndex),
  };
}

KernelQuery _syntheticQuery(int routeIndex) {
  final synthetic = routeIndex - 10;
  return switch (synthetic % 3) {
    0 => KernelQuery('GET', Uri(path: '/generated/r$synthetic/literal')),
    1 => KernelQuery('GET', Uri(path: '/generated/r$synthetic/items/42')),
    _ => KernelQuery(
      'GET',
      Uri(path: '/generated/r$synthetic/items/42/children/91'),
    ),
  };
}

int generatedKernelHash(List<String> values) {
  var hash = 0x811c9dc5;
  for (final value in values) {
    for (final codeUnit in value.codeUnits) {
      hash = ((hash ^ codeUnit) * 0x01000193) & 0x7fffffff;
    }
    hash = ((hash ^ 0xff) * 0x01000193) & 0x7fffffff;
  }
  return hash;
}
