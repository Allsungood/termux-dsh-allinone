import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class TerminalPage extends StatefulWidget {
  const TerminalPage({super.key});

  @override
  State<TerminalPage> createState() => _TerminalPageState();
}

class _TerminalPageState extends State<TerminalPage> {
  final List<String> _output = [];
  final TextEditingController _controller = TextEditingController();
  Process? _shellProcess;
  StreamSubscription<String>? _stdoutSubscription;
  StreamSubscription<String>? _stderrSubscription;
  bool _isRunning = false;
  String _currentDirectory = '/data/data/com.termux/files/usr';

  @override
  void initState() {
    super.initState();
    _initializeShell();
  }

  Future<void> _initializeShell() async {
    try {
      // Get shell from environment
      final shell = Platform.environment['SHELL'] ?? '/system/bin/sh';
      
      // Start process in Termux context
      _shellProcess = await Process.start(
        shell,
        ['-l'],
        runInShell: true,
        workingDirectory: _currentDirectory,
      );

      _isRunning = true;
      _addOutput('Termux Shell Ready\n');

      // Listen to stdout
      _stdoutSubscription = _shellProcess!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        if (mounted) {
          setState(() {
            _output.add(line);
            if (_output.length > 1000) {
              _output.removeAt(0);
            }
          });
        }
      });

      // Listen to stderr
      _stderrSubscription = _shellProcess!.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        if (mounted) {
          setState(() {
            _output.add('❌ $line');
          });
        }
      });

      // Handle process exit
      _shellProcess!.exitCode.then((code) {
        if (mounted) {
          setState(() {
            _isRunning = false;
            _addOutput('\nProcess exited with code: $code');
          });
        }
      });
    } catch (e) {
      _addOutput('Error starting shell: $e\n');
    }
  }

  void _addOutput(String text) {
    setState(() {
      _output.add(text);
      if (_output.length > 1000) {
        _output.removeAt(0);
      }
    });
  }

  void _sendCommand(String command) {
    if (_shellProcess != null && _shellProcess!.isAlive && command.trim().isNotEmpty) {
      setState(() {
        _output.add('\u001B[32m$_currentDirectory \$ $command\u001B[0m');
      });
      
      _shellProcess!.stdin.writeln(command);
      _controller.clear();

      // Update current directory for prompt
      if (command.startsWith('cd ')) {
        final path = command.substring(3).trim();
        if (path == '~') {
          _currentDirectory = Platform.environment['HOME'] ?? '/data/data/com.termux/files/usr';
        } else if (path.startsWith('/')) {
          _currentDirectory = path;
        } else {
          _currentDirectory = '${_currentDirectory}/$path';
        }
      }
    }
  }

  void _clearOutput() {
    setState(() {
      _output.clear();
    });
  }

  @override
  void dispose() {
    _stdoutSubscription?.cancel();
    _stderrSubscription?.cancel();
    _shellProcess?.kill();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('终端'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.green,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete),
            tooltip: '清空',
            onPressed: _clearOutput,
          ),
        ],
      ),
      body: Column(
        children: [
          // Output area
          Expanded(
            child: Container(
              color: Colors.black,
              padding: const EdgeInsets.all(8),
              child: ListView.builder(
                controller: ScrollController(),
                itemCount: _output.length,
                itemBuilder: (context, index) {
                  return SelectableText(
                    _output[index],
                    style: const TextStyle(
                      color: Colors.green,
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  );
                },
              ),
            ),
          ),
          
          // Input area
          Container(
            color: Colors.black87,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                const Text(
                  '\$ ',
                  style: TextStyle(
                    color: Colors.green,
                    fontFamily: 'monospace',
                    fontSize: 14,
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'monospace',
                      fontSize: 14,
                    ),
                    decoration: const InputDecoration(
                      hintText: '输入命令...',
                      hintStyle: TextStyle(color: Colors.grey),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    ),
                    onSubmitted: (value) {
                      _sendCommand(value);
                    },
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send, color: Colors.green),
                  onPressed: () {
                    _sendCommand(_controller.text);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}