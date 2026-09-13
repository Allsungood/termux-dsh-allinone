import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/runtime.dart';
import '../models/environment_config.dart';
import '../models/tool_status.dart';

/// Owns the runtime lifecycle: probing what is installed, running first-time
/// setup, and starting/stopping the long running services.
class EnvironmentService {
  EnvironmentService._();

  static final EnvironmentService instance = EnvironmentService._();

  factory EnvironmentService() => instance;

  static const String _configKey = 'environment_config';

  EnvironmentConfig _config = const EnvironmentConfig();
  EnvironmentConfig get config => _config;

  final Map<String, Process> _running = {};
  final Map<String, List<String>> _logs = {};

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _config = EnvironmentConfig.decode(prefs.getString(_configKey));
  }

  Future<void> save(EnvironmentConfig next) async {
    _config = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_configKey, next.encode());
  }

  Future<RuntimePaths> get paths => RuntimePaths.resolve();

  Future<bool> isBootstrapped() async => (await paths).isBootstrapped;

  /// One PRoot invocation answers "what is installed?" for every tool.
  Future<List<ToolStatus>> probe() async {
    final catalog = ToolStatus.catalog(config: _config);
    final runtimePaths = await paths;
    if (!await runtimePaths.proot.exists()) {
      return catalog;
    }
    final proot = ProotRuntime(runtimePaths);
    const script =
        'for t in node npm git python3 dsh openclaw ollama; do '
        'p=\$(command -v "\$t" 2>/dev/null); '
        'if [ -n "\$p" ]; then echo "PRESENT:\$t:\$p"; '
        'else echo "MISSING:\$t"; fi; done';

    final present = <String, String>{};
    try {
      final result = await proot.run(
        const ['/bin/sh', '-c', script],
        timeout: const Duration(seconds: 90),
      );
      for (final raw in result.stdout.toString().split('\n')) {
        final line = raw.trim();
        if (!line.startsWith('PRESENT:')) continue;
        final parts = line.split(':');
        if (parts.length >= 2) {
          present[parts[1]] = parts.length > 2 ? parts.sublist(2).join(':') : '';
        }
      }
    } catch (_) {
      return catalog;
    }

    return catalog
        .map(
          (tool) => tool.copyWith(
            installed: present.containsKey(tool.id),
            executablePath: present[tool.id],
          ),
        )
        .toList();
  }

  Future<void> runSetup({
    required LogFn onLog,
    required ProgressFn onProgress,
  }) async {
    final bootstrap = RuntimeBootstrap(onLog: onLog, onProgress: onProgress);
    await bootstrap.run();
  }

  Future<void> installOllama({
    required LogFn onLog,
    required ProgressFn onProgress,
  }) async {
    final bootstrap = RuntimeBootstrap(onLog: onLog, onProgress: onProgress);
    await bootstrap.installOllama();
  }

  bool isRunning(String toolId) => _running.containsKey(toolId);

  List<String> logsFor(String toolId) =>
      List.unmodifiable(_logs[toolId] ?? const <String>[]);

  /// Start a tool's service as a guest process and keep its output for the UI.
  Future<void> startTool(ToolStatus tool) async {
    final command = tool.startCommand;
    if (command == null || isRunning(tool.id)) return;

    final runtimePaths = await paths;
    final proot = ProotRuntime(runtimePaths);
    final buffer = _logs.putIfAbsent(tool.id, () => <String>[]);
    buffer.add('> $command');

    final process = await Process.start(
      runtimePaths.proot.path,
      proot.guestArgs(['/bin/sh', '-c', command]),
      environment: proot.environment,
      includeParentEnvironment: false,
    );
    _running[tool.id] = process;

    void collect(Stream<List<int>> stream) {
      stream.transform(utf8.decoder).listen((chunk) {
        for (final line in chunk.split('\n')) {
          if (line.trim().isEmpty) continue;
          buffer.add(line.trimRight());
          if (buffer.length > 400) buffer.removeAt(0);
        }
      });
    }

    collect(process.stdout);
    collect(process.stderr);
    unawaited(
      process.exitCode.then((code) {
        buffer.add('-- exited with code $code');
        _running.remove(tool.id);
      }),
    );
  }

  Future<void> stopTool(String toolId) async {
    final process = _running.remove(toolId);
    if (process == null) return;
    process.kill(ProcessSignal.sigterm);
    _logs.putIfAbsent(toolId, () => <String>[]).add('-- stopped');
  }
}
