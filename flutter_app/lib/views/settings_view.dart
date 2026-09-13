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
      setState(() => _validationError = 'Ports must be numbers between 1 and 65535.');
      return;
    }
    if (_ollamaModel.text.trim().isEmpty) {
      setState(() => _validationError = 'Model name cannot be empty.');
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
      const SnackBar(content: Text('Settings saved')),
    );
  }

  Future<void> _rerunSetup() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => TaskPage(
          title: 'Repair environment',
          description:
              'Re-runs the installer. Already downloaded archives are reused, '
              'so this is quick on a device that has been set up before.',
          successMessage: 'Environment is up to date',
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
          'Services',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        _portField(
          label: 'dsh web UI port',
          controller: _dshPort,
          helper: 'Default 3080',
        ),
        _portField(
          label: 'OpenClaw gateway port',
          controller: _openclawPort,
          helper: 'Default 18789',
        ),
        _portField(
          label: 'Ollama port',
          controller: _ollamaPort,
          helper: 'Default 11434',
        ),
        TextField(
          controller: _ollamaModel,
          decoration: const InputDecoration(
            labelText: 'Default Ollama model',
            helperText: 'e.g. llama3.2:1b',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Keep services awake'),
          subtitle: const Text(
            'Foreground services survive Android background limits',
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
          label: const Text('Save settings'),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
        ),
        const SizedBox(height: 28),
        Text(
          'Maintenance',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _rerunSetup,
          icon: const Icon(Icons.build),
          label: const Text('Repair / re-run installation'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
        ),
        const SizedBox(height: 28),
        Text(
          'About',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Everything runs inside this app\'s private storage using PRoot. '
          'No root is required and no separate Termux installation is needed. '
          'The guest is an Ubuntu 24.04 root filesystem with Node.js 22 LTS.',
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
