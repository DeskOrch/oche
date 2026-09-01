import 'dart:io';

import 'package:oche_benchmark_harness/environment_metadata.dart';
import 'package:test/test.dart';

void main() {
  test(
    'captures validation host metadata and honors the environment label',
    () async {
      final metadata = await collectEnvironmentMetadata(
        loadGenerator: 'none',
        ohaPath: 'unused',
        environmentTypeOverride: 'Hyper-V VM',
      );

      expect(metadata['operatingSystem'], Platform.operatingSystem);
      expect(metadata['osVersion'], isA<String>());
      expect(metadata['architecture'], isA<String>());
      expect(metadata['cpuModel'], anyOf(isNull, isA<String>()));
      expect(metadata['logicalCpuCount'], Platform.numberOfProcessors);
      expect(metadata['dartVersion'], Platform.version);
      expect(metadata['environmentType'], 'Hyper-V VM');
      expect(metadata['loadGenerator'], 'none');

      if (Platform.isLinux) {
        expect(metadata['linuxDistribution'], isA<String>());
        expect(metadata['kernelVersion'], isA<String>());
        expect(
          metadata['totalMemoryBytes'],
          isA<int>().having((value) => value, 'bytes', greaterThan(0)),
        );
      }
    },
  );
}
