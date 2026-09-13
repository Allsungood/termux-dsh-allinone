import 'package:flutter/material.dart';

import '../models/environment_config.dart';
import '../pages/task_page.dart';
import '../services/environment_service.dart';

/// Ports, defaults and maintenance actions.
class SettingsView extends StatefulWidget {
  const SettingsView({super.key});

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  final EnvironmentService _environment = EnvironmentService();

  final TextEditingController _dshPort = TextEditingController();
  final TextEditingController _openclawPort = TextEditingController();
  final TextEditingController _ollamaPort = TextEditingController();
  final TextEditingController _ollamaModel = TextEditingController();

  bool _keepAwake = true;
  bool _loaded = false;
  String? _validationError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _dshPort.dispose();
    _openclawPort.dispose();
    _ollamaPort.dispose();
    _ollamaModel.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    await _environment.load();
    final config = _environment.config;
    _dshPort.text = config.dshPort.toString();
    _openclawPort.text = config.openclawPort.toString();
    _ollamaPort.text = config.ollamaPort.toString();
    _ollamaModel.text = config.ollamaModel;
    _keepAwake = config.keepAwake;
    if (mounted) setState(() => _loaded = true);
  }

  int? _parsePort(String raw) {
    final value = int.tryParse(raw.trim());
    if (value == null || value < 1 || value > 65535) return null;
    return value;
  }

  Future<void> _save() async {
    final dshPort = _parsePort(_dshPort.text);
    final openclawPort = _parsePort(_openclawPort.text);
    final ollamaPort = _parsePort(_ollamaPort.text);

    if (dshPort == null || openclawPort == null || ollamaPort == null) {
      setState(() => _validationError = '端口必须是 1 到 65535 之间的数字。');
      return;
    }
    if (_ollamaModel.text.trim().isEmpty) {
      setState(() => _validationError = '模型名称不能为空。');
      return;
    }

    setState(() => _validationError = null);
    await _environment.save(
      EnvironmentConfig(
        dshPort: dshPort,
        openclawPort: openclawPort,
        ollamaPort: ollamaPort,
        ollamaModel: _ollamaModel.text.trim(),
        keepAwake: _keepAwake,
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('设置已保存')),
    );
  }

  Future<void> _rerunSetup() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => TaskPage(
          title: '修复运行环境',
          description:
              '将重新运行安装程序。已下载的压缩包会被直接复用，'
              '因此在之前安装过的设备上速度很快。',
          successMessage: '运行环境已是最新',
          body: (onLog, onProgress) => _environment.runSetup(
            onLog: onLog,
            onProgress: onProgress,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!_loaded) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Text(
          '服务',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        _portField(
          label: 'dsh Web 界面端口',
          controller: _dshPort,
          helper: '默认 3080',
        ),
        _portField(
          label: 'OpenClaw 网关端口',
          controller: _openclawPort,
          helper: '默认 18789',
        ),
        _portField(
          label: 'Ollama 端口',
          controller: _ollamaPort,
          helper: '默认 11434',
        ),
        TextField(
          controller: _ollamaModel,
          decoration: const InputDecoration(
            labelText: '默认 Ollama 模型',
            helperText: '例如 llama3.2:1b',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('保持服务常驻运行'),
          subtitle: const Text(
            '前台服务可避免被安卓系统回收',
          ),
          value: _keepAwake,
          onChanged: (value) => setState(() => _keepAwake = value),
        ),
        if (_validationError != null) ...[
          const SizedBox(height: 8),
          Text(
            _validationError!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.save),
          label: const Text('保存设置'),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
        ),
        const SizedBox(height: 28),
        Text(
          '维护',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _rerunSetup,
          icon: const Icon(Icons.build),
          label: const Text('修复 / 重新安装'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
        ),
        const SizedBox(height: 28),
        Text(
          '关于',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '所有内容都通过 PRoot 在本应用的私有存储中运行，无需 root 权限，'
          '也无需另外安装 Termux。客户机是一个 Ubuntu 24.04 根文件系统，'
          '内置 Node.js 22 LTS。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _portField({
    required String label,
    required TextEditingController controller,
    required String helper,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: label,
          helperText: helper,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}
