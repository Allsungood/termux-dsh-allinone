import 'package:flutter/material.dart';

import '../models/tool_status.dart';

/// One tool on the dashboard: state plus the actions that make sense for it.
class ToolCard extends StatelessWidget {
  const ToolCard({
    super.key,
    required this.tool,
    required this.running,
    this.onOpen,
    this.onStart,
    this.onStop,
    this.onInstall,
  });

  final ToolStatus tool;
  final bool running;
  final VoidCallback? onOpen;
  final VoidCallback? onStart;
  final VoidCallback? onStop;
  final VoidCallback? onInstall;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final installed = tool.installed;

    final Color accent;
    if (running) {
      accent = Colors.green;
    } else if (installed) {
      accent = scheme.primary;
    } else {
      accent = scheme.outline;
    }

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(tool.icon, size: 20, color: accent),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    tool.name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _StateDot(color: accent, filled: installed),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              tool.description,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            Text(
              running
                  ? 'running'
                  : (installed ? 'installed' : (tool.optional ? 'not installed' : 'missing')),
              style: theme.textTheme.labelSmall?.copyWith(color: accent),
            ),
            const Spacer(),
            if (!installed && tool.optional) ...[
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onInstall,
                  icon: const Icon(Icons.download, size: 16),
                  label: const Text('Install'),
                ),
              ),
            ] else if (installed && tool.startCommand != null) ...[
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: running ? onStop : onStart,
                      child: Text(running ? 'Stop' : 'Start'),
                    ),
                  ),
                  if (tool.dashboardUrl != null) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: onOpen,
                        child: const Text('Open'),
                      ),
                    ),
                  ],
                ],
              ),
            ] else
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: null,
                  child: Text(installed ? 'Ready' : 'Unavailable'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StateDot extends StatelessWidget {
  const _StateDot({required this.color, required this.filled});

  final Color color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled ? color : Colors.transparent,
        border: Border.all(color: color, width: 1.5),
      ),
    );
  }
}
