import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/runtime.dart';

/// 一个需要长时间运行的任务：显示进度和实时日志。
typedef TaskBody = Future<void> Function(LogFn onLog, ProgressFn onProgress);

/// 通用的“执行任务并显示过程”页面。
///
/// 用于可选的 Ollama 安装和修复安装，让用户始终看到真实输出而不是一个转圈。
class TaskPage extends StatefulWidget {
  const TaskPage({
    super.key,
    required this.title,
    required this.body,
    this.description,
    this.successMessage = '已完成',
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
  String _label = '正在开始…';
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

  Future<void> _copyLogs() async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: _logs.join('\n')));
    messenger.showSnackBar(
      const SnackBar(content: Text('日志已复制，可直接粘贴反馈')),
    );
  }

  Future<void> _run() async {
    setState(() {
      _running = true;
      _done = false;
      _error = null;
      _logs.clear();
      _progress = 0;
      _label = '正在开始…';
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
        _label = '失败';
      });
      _append('错误：$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
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
              const SizedBox(height: 14),
              Expanded(
                child: Container(
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
                ),
              ),
              const SizedBox(height: 14),
              if (_done)
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).pop(true),
                  icon: const Icon(Icons.check),
                  label: const Text('关闭'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                )
              else if (_error != null)
                FilledButton.icon(
                  onPressed: _run,
                  icon: const Icon(Icons.refresh),
                  label: const Text('重试'),
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
