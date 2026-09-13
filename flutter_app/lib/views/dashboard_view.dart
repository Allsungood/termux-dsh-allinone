import 'dart:async';

import 'package:flutter/material.dart';

import '../models/tool_status.dart';
import '../pages/task_page.dart';
import '../pages/web_dashboard_page.dart';
import '../services/environment_service.dart';
import '../widgets/status_card.dart';
import '../widgets/tool_card.dart';

/// Tool grid with live state.
class DashboardView extends StatefulWidget {
  const DashboardView({super.key});

  @override
  State<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<DashboardView> {
  final EnvironmentService _environment = EnvironmentService();

  List<ToolStatus> _tools = ToolStatus.catalog();
  bool _loading = true;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _refresh();
    // Cheap repaint so the running/stopped dots follow the real processes.
    _ticker = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (mounted) setState(() => _loading = true);
    final tools = await _environment.probe();
    if (!mounted) return;
    setState(() {
      _tools = tools;
      _loading = false;
    });
  }

  void _open(ToolStatus tool) {
    final url = tool.dashboardUrl;
    if (url == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WebDashboardPage(url: url, title: tool.name),
      ),
    );
  }

  Future<void> _installOllama() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => TaskPage(
          title: 'Install Ollama',
          description:
              'Ollama ships as a ~1.5 GB archive. Keep the screen on and stay '
              'on Wi-Fi — this takes a while.',
          successMessage: 'Ollama installed',
          body: (onLog, onProgress) => _environment.installOllama(
            onLog: onLog,
            onProgress: onProgress,
          ),
        ),
      ),
    );
    if (changed == true) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final installed = _tools.where((tool) => tool.installed).length;

    if (_loading && _tools.every((tool) => !tool.installed)) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          StatusCard(
            icon: Icons.developer_board,
            title: 'Linux runtime',
            subtitle: '$installed of ${_tools.length} tools ready inside the app sandbox',
            accent: installed == _tools.length ? Colors.green : null,
          ),
          const SizedBox(height: 16),
          Text(
            'Tools',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth > 620 ? 3 : 2;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _tools.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 0.82,
                ),
                itemBuilder: (context, index) {
                  final tool = _tools[index];
                  return ToolCard(
                    tool: tool,
                    running: _environment.isRunning(tool.id),
                    onOpen: () => _open(tool),
                    onStart: () => _environment.startTool(tool),
                    onStop: () => _environment.stopTool(tool.id),
                    onInstall: tool.id == 'ollama' ? _installOllama : null,
                  );
                },
              );
            },
          ),
          const SizedBox(height: 20),
          Card(
            elevation: 0,
            color: theme.colorScheme.surfaceContainerHighest,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Quick commands',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const SelectableText(
                    'dsh web --port 3080\n'
                    'openclaw gateway\n'
                    'ollama serve && ollama pull llama3.2:1b\n'
                    'git --version && python3 --version',
                    style: TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Run these in the Console tab.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
