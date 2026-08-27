/// Small, auditable environment snapshot for benchmark interpretation.
library;

import 'dart:ffi';
import 'dart:io';

/// Captures platform facts relevant to comparing benchmark trials.
Future<Map<String, Object>> collectEnvironmentMetadata({
  required String loadGenerator,
  required String ohaPath,
  String? environmentTypeOverride,
}) async {
  final cpuModel = await _cpuModel();
  final loadGeneratorVersion = loadGenerator == 'oha'
      ? await _commandVersion(ohaPath, const ['--version'])
      : null;
  return {
    'operatingSystem': Platform.operatingSystem,
    'osVersion': Platform.operatingSystemVersion,
    'architecture': Abi.current().toString(),
    'dartVersion': Platform.version,
    'cpuModel': ?cpuModel,
    'logicalCpuCount': Platform.numberOfProcessors,
    'environmentType':
        environmentTypeOverride ?? await _detectEnvironmentType(),
    'loadGenerator': loadGenerator,
    'loadGeneratorVersion': ?loadGeneratorVersion,
  };
}

Future<String> _detectEnvironmentType() async {
  if (Platform.isWindows) return 'native-windows';
  if (Platform.isMacOS) return 'native-macos';
  if (!Platform.isLinux) return 'unknown';

  final kernel = await _readIfAvailable('/proc/sys/kernel/osrelease');
  final version = await _readIfAvailable('/proc/version');
  final linuxIdentity = '${kernel ?? ''} ${version ?? ''}'.toLowerCase();
  final isWsl = linuxIdentity.contains('microsoft');
  final isWsl2 =
      linuxIdentity.contains('wsl2') ||
      linuxIdentity.contains('microsoft-standard');
  final isContainer =
      File('/.dockerenv').existsSync() ||
      (await _readIfAvailable('/proc/1/cgroup'))?.contains('docker') == true;

  if (isWsl2 && isContainer) return 'wsl2-container';
  if (isWsl2) return 'wsl2';
  if (isWsl) return 'wsl';
  if (isContainer) return 'linux-container';
  return 'native-linux';
}

Future<String?> _cpuModel() async {
  if (Platform.isWindows) {
    final result = await _commandVersion('powershell.exe', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      r"(Get-ItemProperty -LiteralPath 'Registry::HKEY_LOCAL_MACHINE\HARDWARE\DESCRIPTION\System\CentralProcessor\0' -Name ProcessorNameString).ProcessorNameString",
    ]);
    return result ?? Platform.environment['PROCESSOR_IDENTIFIER'];
  }
  if (Platform.isLinux) {
    final cpuInfo = await _readIfAvailable('/proc/cpuinfo');
    if (cpuInfo == null) return null;
    for (final line in cpuInfo.split('\n')) {
      if (line.startsWith('model name') || line.startsWith('Hardware')) {
        final separator = line.indexOf(':');
        if (separator >= 0) return line.substring(separator + 1).trim();
      }
    }
  }
  if (Platform.isMacOS) {
    return _commandVersion('sysctl', const ['-n', 'machdep.cpu.brand_string']);
  }
  return null;
}

Future<String?> _readIfAvailable(String path) async {
  try {
    return (await File(path).readAsString()).trim();
  } on FileSystemException {
    return null;
  }
}

Future<String?> _commandVersion(
  String executable,
  List<String> arguments,
) async {
  try {
    final result = await Process.run(executable, arguments);
    if (result.exitCode != 0) return null;
    final value = (result.stdout as String).trim();
    return value.isEmpty ? null : value;
  } on ProcessException {
    return null;
  }
}
