import 'package:flutter/material.dart';

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
  static List<ToolStatus> catalog() => const [
    ToolStatus(
      id: 'dsh',
      name: 'dsh',
      description: 'DeepSeek Harness — AI coding agent with a web UI',
      icon: Icons.terminal,
      dashboardUrl: 'http://127.0.0.1:3080',
      startCommand: 'dsh web --port 3080 --host 127.0.0.1',
    ),
    ToolStatus(
      id: 'openclaw',
      name: 'OpenClaw',
      description: 'AI gateway with device capabilities',
      icon: Icons.hub,
      dashboardUrl: 'http://127.0.0.1:18789',
      startCommand: 'openclaw gateway',
    ),
    ToolStatus(
      id: 'ollama',
      name: 'Ollama',
      description: 'Local LLM inference (~1.5 GB download)',
      icon: Icons.memory,
      optional: true,
      startCommand: 'ollama serve',
    ),
    ToolStatus(
      id: 'node',
      name: 'Node.js',
      description: 'JavaScript runtime (v22 LTS)',
      icon: Icons.javascript,
    ),
    ToolStatus(
      id: 'git',
      name: 'Git',
      description: 'Distributed version control',
      icon: Icons.commit,
    ),
    ToolStatus(
      id: 'python3',
      name: 'Python 3',
      description: 'Scripting and build tooling',
      icon: Icons.code,
    ),
  ];
}
