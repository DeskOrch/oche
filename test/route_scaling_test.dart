import 'package:oche_benchmark_harness/route_scaling.dart';
import 'package:test/test.dart';

void main() {
  for (final routeCount in [10, 100, 1000]) {
    test('all strategies resolve $routeCount routes and reject misses', () {
      final routes = generateSyntheticRoutes(routeCount);
      final strategies = <SyntheticRouteLookup>[
        LinearRouteLookup(routes),
        SegmentedRouteLookup(routes),
        HashRouteLookup(routes),
      ];

      for (final strategy in strategies) {
        for (var index = 0; index < routes.length; index++) {
          expect(
            strategy.lookup(routes[index]),
            index,
            reason: '${strategy.name} failed at route $index',
          );
        }
        expect(strategy.lookup('/missing'), -1);
        expect(strategy.lookup('/g0/route-not-an-index'), -1);
      }
    });
  }
}
