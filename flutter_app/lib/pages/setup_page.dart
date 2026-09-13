import 'package:flutter/material.dart';

import '../services/environment_service.dart';
import 'home_page.dart';

/// First-run screen: installs the PRoot runtime and the Linux toolchain.
class SetupPage extends StatefulWidget {
  const SetupPage({super.key});

  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  final EnvironmentService _environment = EnvironmentService();
  final List<String> _logs = <String>[];
  final ScrollController _scroll = ScrollController();

  double _progress = 0;
  String _label = 'Ready when you are';
  bool _running = false;
  bool _done = false;
  String? _error;

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

  Future<void> _start() async {
    setState(() {
      _running = true;
      _done = false;
      _error = null;
      _logs.clear();
      _progress = 0;
      _label = 'Starting';
    });

    try {
      await _environment.runSetup(
        onLog: _append,
        onProgress: (value, label) {
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
        _label = 'Setup complete';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _running = false;
        _error = error.toString();
        _label = 'Setup failed';
      });
      _append('ERROR: $error');
    }
  }

  void _enterApp() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const HomePage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(theme),
              const SizedBox(height: 16),
              if (_running || _done || _error != null) _progressBlock(theme),
              if (_logs.isNotEmpty) ...[
                const SizedBox(height: 16),
                Expanded(child: _logConsole(theme)),
              ] else
                const Spacer(),
              const SizedBox(height: 16),
              _actions(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(ThemeData theme) {
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _done ? Icons.check_circle : Icons.rocket_launch,
                  size: 36,
                  color: _done ? Colors.green : theme.colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _done ? 'Environment ready' : 'Set up your Linux environment',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              _done
                  ? 'dsh, OpenClaw and the toolchain are installed inside the app sandbox.'
                  : 'This installs a self-contained Linux runtime inside the app — '
                        'no root, no separate Termux install. First run downloads '
                        'about 55 MB.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: const [
                _Chip(icon: Icons.terminal, label: 'dsh'),
                _Chip(icon: Icons.hub, label: 'OpenClaw'),
                _Chip(icon: Icons.javascript, label: 'Node.js 22'),
                _Chip(icon: Icons.commit, label: 'Git'),
                _Chip(icon: Icons.code, label: 'Python 3'),
                _Chip(icon: Icons.memory, label: 'Ollama (optional)'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _progressBlock(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(_label, style: theme.textTheme.bodyMedium),
            ),
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
              _error != null ? theme.colorScheme.error : theme.colorScheme.primary,
            ),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _error!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
      ],
    );
  }

  Widget _logConsole(ThemeData theme) {
    return Container(
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
          final isError = line.startsWith('ERROR') || line.startsWith('WARNING');
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
    );
  }

  Widget _actions() {
    if (_done) {
      return FilledButton.icon(
        onPressed: _enterApp,
        icon: const Icon(Icons.arrow_forward),
        label: const Text('Open dashboard'),
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
        ),
      );
    }
    return FilledButton.icon(
      onPressed: _running ? null : _start,
      icon: _running
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.download),
      label: Text(
        _running
            ? 'Installing…'
            : (_error == null ? 'Install environment' : 'Retry installation'),
      ),
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14),
          const SizedBox(width: 6),
          Text(label, style: theme.textTheme.labelMedium),
        ],
      ),
    );
  }
}
