import 'package:flutter/material.dart';

import 'environment_config.dart';

/// A tool that lives inside the guest root filesystem.
class ToolStatus {
  const ToolStatus({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    this.installed = false,
    this.executablePath,
    this.dashboardUrl,
    this.startCommand,
    this.optional = false,
  });

  final String id;
  final String name;
  final String description;
  final IconData icon;
  final bool installed;
  final String? executablePath;

  /// Local URL to open in the in-app WebView, when the tool serves one.
  final String? dashboardUrl;

  /// Guest command that starts the tool's long running service.
  final String? startCommand;

  /// Optional tools are not installed by the default setup run.
  final bool optional;

  ToolStatus copyWith({bool? installed, String? executablePath}) {
    return ToolStatus(
      id: id,
      name: name,
      description: description,
      icon: icon,
      installed: installed ?? this.installed,
      executablePath: executablePath ?? this.executablePath,
      dashboardUrl: dashboardUrl,
      startCommand: startCommand,
      optional: optional,
    );
  }

  /// The catalogue shown on the dashboard, in display order.
  ///
  /// Start commands and dashboard URLs are derived from the saved [config], so
  /// changing a port in Settings actually changes what gets launched.
  static List<ToolStatus> catalog({
    EnvironmentConfig config = const EnvironmentConfig(),
  }) => [
    ToolStatus(
      id: 'dsh',
      name: 'dsh',
      description: 'DeepSeek Harness —— 带 Web 界面的 AI 编程助手',
      icon: Icons.terminal,
      dashboardUrl: 'http://127.0.0.1:${config.dshPort}',
      startCommand:
          'dsh web --port ${config.dshPort} --host 127.0.0.1',
    ),
    ToolStatus(
      id: 'openclaw',
      name: 'OpenClaw',
      description: '具备设备能力的 AI 网关',
      icon: Icons.hub,
      dashboardUrl: 'http://127.0.0.1:${config.openclawPort}',
      startCommand: 'openclaw gateway --port ${config.openclawPort}',
    ),
    ToolStatus(
      id: 'ollama',
      name: 'Ollama',
      description: '本地大模型推理（约 1.5 GB 下载）',
      icon: Icons.memory,
      optional: true,
      dashboardUrl: 'http://127.0.0.1:${config.ollamaPort}',
      startCommand:
          'OLLAMA_HOST=127.0.0.1:${config.ollamaPort} ollama serve',
    ),
    const ToolStatus(
      id: 'node',
      name: 'Node.js',
      description: 'JavaScript 运行时（v22 LTS）',
      icon: Icons.javascript,
    ),
    const ToolStatus(
      id: 'git',
      name: 'Git',
      description: '分布式版本控制',
      icon: Icons.commit,
    ),
    const ToolStatus(
      id: 'python3',
      name: 'Python 3',
      description: '脚本与构建工具链',
      icon: Icons.code,
    ),
  ];
}
