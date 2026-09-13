import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';

class TerminalService {
  Process? _process;
  StreamSubscription<String>? _outputSubscription;
  final _outputController = StreamController<String>.broadcast();
  final _errorController = StreamController<String>.broadcast();

  Stream<String> get output => _outputController.stream;
  Stream<String> get error => _errorController.stream;

  bool get isRunning => _process != null && _process!.isAlive;

  // Start a shell process in Termux environment
  Future<bool> startShell() async {
    try {
      // Termux-specific shell invocation
      final shell = Platform.environment['SHELL'] ?? '/system/bin/sh';

      _process = await Process.start(
        shell,
        ['-l'],
        runInShell: true,
        environment: Map<String, String>.from(Platform.environment),
      );

      _outputSubscription = _process!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        _outputController.add(line);
      }, onDone: () {
        _outputController.close();
      }, onError: (error) {
        _errorController.add(error.toString());
      });

      _process!.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        _errorController.add(line);
      });

      return true;
    } catch (e) {
      return false;
    }
  }

  // Send command to the shell
  Future<void> sendCommand(String command) async {
    if (_process != null && _process!.isAlive) {
      _process!.stdin.writeln(command);
    }
  }

  // Run a command and return its output
  Future<String> runCommand(String command, {Duration timeout = const Duration(seconds: 30)}) async {
    try {
      final result = await Process.run(
        command.split(' ')[0],
        command.split(' ').skip(1).toList(),
        runInShell: true,
        timeout: timeout,
      );
      return result.stdout.toString();
    } catch (e) {
      return 'Error: $e';
    }
  }

  // Get shell history (last N commands)
  Future<List<String>> getHistory({int limit = 50}) async {
    final historyPath = '${Platform.environment['HOME']}/.bash_history';
    try {
      final file = File(historyPath);
      if (await file.exists()) {
        final lines = await file.readAsLines();
        return lines.takeLast(limit).toList();
      }
    } catch (e) {
      // Ignore
    }
    return [];
  }

  // Execute an interactive command (like `su` or `proot-distro login`)
  Future<Process> startInteractiveProcess(String command) async {
    return Process.start(command, [], runInShell: true);
  }

  // Cleanup
  void dispose() {
    _outputSubscription?.cancel();
    _process?.kill();
    _process = null;
    _outputController.close();
    _errorController.close();
  }
}