import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/environment_service.dart';
import '../models/environment_config.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final EnvironmentService _envService = EnvironmentService();
  late EnvironmentConfig _config;
  bool _isLoading = true;

  // Form controllers
  final TextEditingController _dshPortController = TextEditingController();
  final TextEditingController _openclawPortController = TextEditingController();
  final TextEditingController _ollamaPortController = TextEditingController();
  final TextEditingController _ollamaModelController = TextEditingController();

  // Checkbox values
  bool _autoStartAtBoot = true;
  bool _disableBatteryOptimization = true;
  bool _requestPermissionsOnStartup = true;
  String _approvalPolicy = 'never';

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    setState(() {
      _isLoading = true;
    });
    _config = await _envService.loadConfig();
    
    // Populate form fields
    _dshPortController.text = _config.dshWebPort;
    _openclawPortController.text = _config.openclawPort.toString();
    _ollamaPortController.text = _config.ollamaPort;
    _ollamaModelController.text = _config.openclawModel; // Reuse for now
    _autoStartAtBoot = _config.autoStartAtBoot;
    _disableBatteryOptimization = _config.disableBatteryOptimization;
    _requestPermissionsOnStartup = _config.requestPermissionsOnStartup;
    _approvalPolicy = _config.dshApprovalPolicy;
    
    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _saveConfig() async {
    setState(() {
      _isLoading = true;
    });
    
    // Update config from form
    final newConfig = EnvironmentConfig(
      dshWebPort: _dshPortController.text,
      dshApprovalPolicy: _approvalPolicy,
      dshAutoStart: true, // Always auto-start for now
      openclawPort: int.tryParse(_openclawPortController.text) ?? 18789,
      openclawModel: _ollamaModelController.text,
      ollamaPort: _ollamaPortController.text,
      autoStartAtBoot: _autoStartAtBoot,
      disableBatteryOptimization: _disableBatteryOptimization,
      requestPermissionsOnStartup: _requestPermissionsOnStartup,
    );
    
    await _envService.saveConfig(newConfig);
    setState(() {
      _isLoading = false;
    });
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('设置已保存')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _saveConfig,
            child: const Text('保存'),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    '服务配置',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildServiceSection(),
                  const SizedBox(height: 24),
                  const Text(
                    '系统选项',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildSystemSection(),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: _isLoading ? null : _saveConfig,
                    icon: const Icon(Icons.save),
                    label: const Text('保存所有设置'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildServiceSection() {
    return Column(
      children: [
        _buildTextField(
          label: 'dsh Web 端口',
          hint: '例如: 3080',
          controller: _dshPortController,
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 12),
        _buildDropdownButtonFormField(
          label: 'dsh 审批策略',
          value: _approvalPolicy,
          items: const [
            DropdownMenuItem(value: 'never', child: Text('从不询问')),
            DropdownMenuItem(value: 'ask', child: Text('每次询问')),
            DropdownMenuItem(value: 'manual', child: Text('手动模式')),
          ],
          onChanged: (value) {
            setState(() {
              _approvalPolicy = value!;
            });
          },
        ),
        const SizedBox(height: 12),
        _buildTextField(
          label: 'OpenClaw 端口',
          hint: '例如: 18789',
          controller: _openclawPortController,
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 12),
        _buildTextField(
          label: 'Ollama 端口',
          hint: '例如: 11434',
          controller: _ollamaPortController,
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 12),
        _buildTextField(
          label: '默认 Ollama 模型',
          hint: '例如: llama3.2:1b',
          controller: _ollamaModelController,
        ),
      ],
    );
  }

  Widget _buildSystemSection() {
    return Column(
      children: [
        SwitchListTile(
          title: const Text('开机自动启动'),
          subtitle: const Text('设备启动时自动启动服务'),
          value: _autoStartAtBoot,
          onChanged: (value) {
            setState(() {
              _autoStartAtBoot = value;
            });
          },
        ),
        SwitchListTile(
          title: const Text('禁用电池优化'),
          subtitle: const Text('防止系统杀死后台服务'),
          value: _disableBatteryOptimization,
          onChanged: (value) {
            setState(() {
              _disableBatteryOptimization = value;
            });
          },
        ),
        SwitchListTile(
          title: const Text('启动时请求权限'),
          subtitle: const Text('请求必要的 Android 权限'),
          value: _requestPermissionsOnStartup,
          onChanged: (value) {
            setState(() {
              _requestPermissionsOnStartup = value;
            });
          },
        ),
      ],
    );
  }

  Widget _buildTextField({
    required String label,
    required String hint,
    required TextEditingController controller,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
      ),
      keyboardType: keyboardType,
    );
  }

  Widget _buildDropdownButtonFormField({
    required String label,
    required String value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      value: value,
      items: items,
      onChanged: onChanged,
    );
  }
}