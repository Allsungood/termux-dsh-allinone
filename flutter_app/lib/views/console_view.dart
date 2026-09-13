import 'dart:async';

import 'package:flutter/material.dart';

import '../services/terminal_service.dart';

/// On-screen console backed by a long-lived guest shell.
class ConsoleView extends StatefulWidget {
  const ConsoleView({super.key});

  @override
  State<ConsoleView> createState() => _ConsoleViewState();
}

class _ConsoleViewState extends State<ConsoleView> {
  final TerminalService _terminal = TerminalService();
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final List<String> _lines = <String>[];
  final StringBuffer _partial = StringBuffer();

  StreamSubscription<String>? _subscription;
  bool _booting = true;

  static const List<String> _quickCommands = [
    'dsh --version',
    'dsh web --port 3080',
    'openclaw gateway',
    'ollama list',
    'node --version',
    'python3 --version',
  ];

  @override
  void initState() {
    super.initState();
    _subscription = _terminal.output.listen(_onData);
    _boot();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    try {
      await _terminal.start();
    } catch (error) {
      _append('无法启动终端：$error');
    }
    if (mounted) setState(() => _booting = false);
  }

  void _onData(String chunk) {
    if (!mounted) return;
    setState(() {
      _partial.write(chunk);
      final text = _partial.toString();
      final parts = text.split('\n');
      if (parts.length > 1) {
        for (var i = 0; i < parts.length - 1; i++) {
          _lines.add(parts[i]);
        }
        _partial
          ..clear()
          ..write(parts.last);
        if (_lines.length > 2000) {
          _lines.removeRange(0, _lines.length - 2000);
        }
      }
    });
    _scrollToBottom();
  }

  void _append(String line) {
    if (!mounted) return;
    setState(() => _lines.add(line));
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  void _submit(String raw) {
    final command = raw.trim();
    if (command.isEmpty) return;
    _append('> $command');
    _terminal.send(command);
    _input.clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            itemCount: _quickCommands.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final command = _quickCommands[index];
              return ActionChip(
                label: Text(
                  command,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                ),
                onPressed: () {
                  _input.text = command;
                  _submit(command);
                },
              );
            },
          ),
        ),
        Expanded(
          child: Container(
            width: double.infinity,
            color: const Color(0xFF0E1016),
            padding: const EdgeInsets.all(12),
            child: _booting
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    controller: _scroll,
                    itemCount: _lines.length + 1,
                    itemBuilder: (context, index) {
                      final isPartial = index == _lines.length;
                      final text = isPartial ? _partial.toString() : _lines[index];
                      if (text.isEmpty && isPartial) {
                        return const SizedBox.shrink();
                      }
                      final isCommand = text.startsWith('> ');
                      return SelectableText(
                        text,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          height: 1.4,
                          color: isCommand
                              ? const Color(0xFF7DD3FC)
                              : const Color(0xFFD4D4D4),
                        ),
                      );
                    },
                  ),
          ),
        ),
        SafeArea(
          top: false,
          child: Container(
            color: theme.colorScheme.surfaceContainerHighest,
            padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
            child: Row(
              children: [
                const Text(
                  '\$',
                  style: TextStyle(fontFamily: 'monospace', fontSize: 14),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _input,
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: TextInputAction.send,
                    onSubmitted: _submit,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                    decoration: const InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: '输入命令',
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: () => _submit(_input.text),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
