import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/environment_service.dart';
import 'home_page.dart';

/// 首屏：把 PRoot 运行时和 Linux 工具链装进 App 私有目录。
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
  String _label = '准备就绪，点击下方按钮开始';
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

  Future<void> _copyLogs() async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: _logs.join('\n')));
    messenger.showSnackBar(
      const SnackBar(content: Text('日志已复制，可直接粘贴反馈')),
    );
  }

  Future<void> _start() async {
    setState(() {
      _running = true;
      _done = false;
      _error = null;
      _logs.clear();
      _progress = 0;
      _label = '正在开始…';
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
        _label = '安装完成';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _running = false;
        _error = error.toString();
        _label = '安装失败';
      });
      _append('错误：$error');
      _append('可点击右上角「复制日志」把上面内容发出来定位问题。');
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
      appBar: AppBar(
        title: const Text('AI 开发环境'),
        centerTitle: true,
        actions: [
          if (_logs.isNotEmpty)
            IconButton(
              tooltip: '复制日志',
              icon: const Icon(Icons.copy_all),
              onPressed: _copyLogs,
            ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(theme),
              const SizedBox(height: 14),
              if (_running || _done || _error != null) _progressBlock(theme),
              if (_logs.isNotEmpty) ...[
                const SizedBox(height: 14),
                Expanded(child: _logConsole(theme)),
              ] else
                const Spacer(),
              const SizedBox(height: 14),
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _done ? Icons.check_circle : Icons.rocket_launch,
                  size: 34,
                  color: _done ? Colors.green : theme.colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _done ? '环境已就绪' : '一键安装 Linux 环境',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              _done
                  ? 'dsh、OpenClaw 和整套工具链已装在本 App 内，无需 root，也不用另外装 Termux。'
                  : '全部安装在 App 自己的目录里，不需要 root，也不依赖其他软件。'
                        '首次运行需要联网下载约 55 MB。',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            const Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _Chip(icon: Icons.terminal, label: 'dsh'),
                _Chip(icon: Icons.hub, label: 'OpenClaw'),
                _Chip(icon: Icons.javascript, label: 'Node.js 22'),
                _Chip(icon: Icons.commit, label: 'Git'),
                _Chip(icon: Icons.code, label: 'Python 3'),
                _Chip(icon: Icons.memory, label: 'Ollama（可选）'),
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
            Expanded(child: Text(_label, style: theme.textTheme.bodyMedium)),
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
        if (_error != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '失败原因',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  _error!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
              ],
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
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.all(12),
      child: ListView.builder(
        controller: _scroll,
        itemCount: _logs.length,
        itemBuilder: (context, index) {
          final line = _logs[index];
          final isProblem =
              line.startsWith('错误') ||
              line.startsWith('警告') ||
              line.startsWith('注意：');
          return SelectableText(
            line,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 11.5,
              height: 1.45,
              color: isProblem
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
        label: const Text('进入主界面'),
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
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
            ? '正在安装…'
            : (_error == null ? '开始安装' : '重试安装'),
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
