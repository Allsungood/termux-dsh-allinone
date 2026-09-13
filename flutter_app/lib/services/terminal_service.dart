import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/runtime.dart';

/// Bridges a long-lived guest shell to the on-screen console.
///
/// The shell is a plain pipe rather than a PTY: full-screen curses programs are
/// not supported, but every ordinary command (and therefore the documented
/// setup steps) works.
class TerminalService {
  TerminalService._();

  static final TerminalService instance = TerminalService._();

  factory TerminalService() => instance;

  Process? _process;
  final StreamController<String> _output =
      StreamController<String>.broadcast();

  Stream<String> get output => _output.stream;

  bool get isRunning => _process != null;

  Future<void> start() async {
    if (_process != null) return;

    final paths = await RuntimePaths.resolve();
    if (!await paths.proot.exists()) {
      _output.add('Runtime is not installed yet. Run setup first.\n');
      return;
    }

    final proot = ProotRuntime(paths);
    final process = await Process.start(
      paths.proot.path,
      proot.guestArgs(const ['/bin/sh']),
      environment: proot.environment,
      includeParentEnvironment: false,
    );
    _process = process;

    void forward(Stream<List<int>> stream) {
      stream
          .transform(utf8.decoder)
          .listen(
            _output.add,
            onError: (Object error) => _output.add('\n$error\n'),
          );
    }

    forward(process.stdout);
    forward(process.stderr);
    unawaited(
      process.exitCode.then((code) {
        _output.add('\n[shell exited with code $code]\n');
        _process = null;
      }),
    );
  }

  void send(String command) {
    final process = _process;
    if (process == null) return;
    process.stdin.writeln(command);
  }

  Future<void> stop() async {
    final process = _process;
    _process = null;
    process?.kill(ProcessSignal.sigterm);
  }
}
