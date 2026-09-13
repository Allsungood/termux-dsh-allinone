import 'package:flutter/material.dart';

import '../core/runtime.dart';

/// Signature of a long running job that reports progress and log lines.
typedef TaskBody =
    Future<void> Function(LogFn onLog, ProgressFn onProgress);

/// Generic "run this job and show me what it is doing" screen.
///
/// Used for optional installs (Ollama) and for re-running the toolchain
/// install, so the user always sees real output instead of a spinner.
class TaskPage extends StatefulWidget {
  const TaskPage({
    super.key,
    required this.title,
    required this.body,
    this.description,
    this.successMessage = 'Done',
  });

  final String title;
  final String? description;
  final TaskBody body;
  final String successMessage;

  @override
  State<TaskPage> createState() => _TaskPageState();
}

class _TaskPageState extends State<TaskPage> {
  final List<String> _logs = <String>[];
  final ScrollController _scroll = ScrollController();

  double _progress = 0;
  String _label = 'Starting';
  bool _running = true;
  bool _done = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _append(String line) {
    if (!mounted) return;
    setState(() => _logs.add(line));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _run() async {
    setState(() {
      _running = true;
      _done = false;
      _error = null;
      _logs.clear();
      _progress = 0;
      _label = 'Starting';
    });
    try {
      await widget.body(
        _append,
        (value, label) {
          if (!mounted) return;
          setState(() {
            _progress = value;
            _label = label;
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _running = false;
        _done = true;
        _progress = 1;
        _label = widget.successMessage;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _running = false;
        _error = error.toString();
        _label = 'Failed';
      });
      _append('ERROR: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.description != null) ...[
                Text(widget.description!, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 12),
              ],
              Row(
                children: [
                  Expanded(child: Text(_label)),
                  Text('${(_progress * 100).round()}%'),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: _progress,
                  minHeight: 8,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    _error != null
                        ? theme.colorScheme.error
                        : theme.colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF11131A),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  padding: const EdgeInsets.all(12),
                  child: ListView.builder(
                    controller: _scroll,
                    itemCount: _logs.length,
                    itemBuilder: (context, index) {
                      final line = _logs[index];
                      final isError =
                          line.startsWith('ERROR') || line.startsWith('WARNING');
                      return SelectableText(
                        line,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11.5,
                          height: 1.45,
                          color: isError
                              ? const Color(0xFFFF8A80)
                              : const Color(0xFF9BE39B),
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (_done)
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).pop(true),
                  icon: const Icon(Icons.check),
                  label: const Text('Close'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                )
              else if (_error != null)
                FilledButton.icon(
                  onPressed: _run,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                )
              else
                const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }
}
