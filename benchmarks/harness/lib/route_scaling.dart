/// Synthetic static route-table lookup strategies for Phase 0.5.
library;

/// A route lookup returns its stable route index, or `-1` for a miss.
abstract interface class SyntheticRouteLookup {
  String get name;

  int lookup(String path);
}

/// Generates deterministic literal routes without code-generation machinery.
List<String> generateSyntheticRoutes(int count) {
  if (count < 1) throw RangeError.range(count, 1, null, 'count');
  return List.generate(
    count,
    (index) => '/g${index % 10}/route$index',
    growable: false,
  );
}

/// O(n) lower-complexity reference strategy.
final class LinearRouteLookup implements SyntheticRouteLookup {
  LinearRouteLookup(this._routes);

  final List<String> _routes;

  @override
  String get name => 'linear_scan';

  @override
  int lookup(String path) => _routes.indexOf(path);
}

/// Hash-assisted static lookup, representative of a prebuilt literal table.
final class HashRouteLookup implements SyntheticRouteLookup {
  HashRouteLookup(List<String> routes)
    : _routes = {
        for (var index = 0; index < routes.length; index++)
          routes[index]: index,
      };

  final Map<String, int> _routes;

  @override
  String get name => 'hash_map';

  @override
  int lookup(String path) => _routes[path] ?? -1;
}

/// First-segment dispatch followed by a small literal leaf scan.
///
/// The fixed ten-way split resembles a shallow generated trie while avoiding
/// generated source or a general-purpose runtime router.
final class SegmentedRouteLookup implements SyntheticRouteLookup {
  SegmentedRouteLookup(List<String> routes)
    : _buckets = List.generate(10, (_) => <({int index, String path})>[]) {
    for (var index = 0; index < routes.length; index++) {
      _buckets[index % 10].add((index: index, path: routes[index]));
    }
  }

  final List<List<({int index, String path})>> _buckets;

  @override
  String get name => 'segmented_leaf_scan';

  @override
  int lookup(String path) {
    if (path.length < 4 ||
        path.codeUnitAt(0) != _slash ||
        path.codeUnitAt(1) != _lowercaseG ||
        path.codeUnitAt(3) != _slash) {
      return -1;
    }
    final bucket = path.codeUnitAt(2) - _zero;
    if (bucket < 0 || bucket >= _buckets.length) return -1;
    for (final route in _buckets[bucket]) {
      if (route.path == path) return route.index;
    }
    return -1;
  }
}

const int _slash = 47;
const int _zero = 48;
const int _lowercaseG = 103;
