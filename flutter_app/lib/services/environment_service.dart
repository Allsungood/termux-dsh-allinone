import 'dart:io';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/environment_config.dart';
import '../models/process_info.dart';

class EnvironmentService {
  static const String _setupCompleteKey = 'setup_complete';
  static const String _configKey = 'environment_config';

  // Check if initial setup has been completed
  Future<bool> isSetupComplete() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_setupCompleteKey) ?? false;
  }

  // Mark setup as complete
  Future<void> markSetupComplete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_setupCompleteKey, true);
  }

  // Load saved environment configuration
  Future<EnvironmentConfig> loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final configJson = prefs.getString(_configKey);
    if (configJson != null) {
      // Parse JSON string to EnvironmentConfig
      // For now, return defaults; in a real app, use jsonDecode
      return EnvironmentConfig();
    }
    return EnvironmentConfig();
  }

  // Save environment configuration
  Future<void> saveConfig(EnvironmentConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    // For simplicity, we're not using JSON serialization here
    await prefs.setBool(_setupCompleteKey, true);
  }

  // Check if dsh is installed
  Future<bool> isDshInstalled() async {
    try {
      final result = await Process.run('which', ['dsh']);
      return result.exitCode == 0;
    } catch (e) {
      return false;
    }
  }

  // Check if openclaw is installed
  Future<bool> isOpenclawInstalled() async {
    try {
      final result = await Process.run('which', ['openclawx']);
      return result.exitCode == 0;
    } catch (e) {
      return false;
    }
  }

  // Check if ollama is installed
  Future<bool> isOllamaInstalled() async {
    try {
      final result = await Process.run('which', ['ollama']);
      return result.exitCode == 0;
    } catch (e) {
      return false;
    }
  }

  // Get all process statuses
  Future<List<ProcessInfo>> getProcessStatuses() async {
    final dshInstalled = await isDshInstalled();
    final openclawInstalled = await isOpenclawInstalled();
    final ollamaInstalled = await isOllamaInstalled();

    return [
      ProcessInfo(
        name: 'dsh',
        displayName: 'dsh (DeepSeek Harness)',
        isRunning: dshInstalled,
        version: dshInstalled ? await _getVersion('dsh', ['--version']) : null,
        description: 'AI coding assistant with Web UI',
      ),
      ProcessInfo(
        name: 'openclaw',
        displayName: 'OpenClaw AI Gateway',
        isRunning: openclawInstalled,
        version: openclawInstalled ? await _getVersion('openclawx', ['--version']) : null,
        description: 'AI gateway with Node device capabilities',
      ),
      ProcessInfo(
        name: 'ollama',
        displayName: 'Ollama LLM Runner',
        isRunning: ollamaInstalled,
        version: ollamaInstalled ? await _getVersion('ollama', ['--version']) : null,
        description: 'Local LLM inference',
      ),
    ];
  }

  Future<String?> _getVersion(String command, List<String> args) async {
    try {
      final result = await Process.run(command, args);
      if (result.exitCode == 0) {
        return result.stdout.toString().trim();
      }
    } catch (e) {
      // Ignore
    }
    return null;
  }

  // Run the one-time setup script
  Future<bool> runSetupScript({
    required Function(String) onProgress,
    bool autoYes = true,
  }) async {
    try {
      // Write setup script to a temp file and execute
      final scriptContent = '''
#!/data/data/com.termux/files/usr/bin/bash
export DSH_APPROVE_POLICY=${autoYes ? 'never' : 'ask'}
export DSH_ASSUME_YES=1

# Run setup scripts
if [ -f "\$HOME/scripts/setup-dsh.sh" ]; then
    echo "Setting up dsh..."
    bash \$HOME/scripts/setup-dsh.sh
fi

if [ -f "\$HOME/scripts/setup-openclaw.sh" ]; then
    echo "Setting up openclaw..."
    bash \$HOME/scripts/setup-openclaw.sh
fi

if [ -f "\$HOME/scripts/setup-ollama.sh" ]; then
    echo "Setting up ollama..."
    bash \$HOME/scripts/setup-ollama.sh
fi

echo "Setup completed!"
''';

      // Write script
      final scriptPath = '${Platform.environment['HOME']}/scripts/setup-all.sh';
      await File(scriptPath).writeAsString(scriptContent);

      // Execute
      final result = await Process.run('bash', [scriptPath]);
      
      onProgress(result.stdout.toString());
      
      if (result.exitCode == 0) {
        await markSetupComplete();
        return true;
      }
      return false;
    } catch (e) {
      onProgress('Error: $e');
      return false;
    }
  }

  // Start dsh web server
  Future<bool> startDshWeb({int port = 3080}) async {
    try {
      // Run in background
      await Process.start('dsh', ['web', '--port', port.toString()], mode: ProcessStartMode.detached);
      return true;
    } catch (e) {
      return false;
    }
  }

  // Start openclaw gateway
  Future<bool> startOpenclaw() async {
    try {
      await Process.start('openclawx', ['start'], mode: ProcessStartMode.detached);
      return true;
    } catch (e) {
      return false;
    }
  }

  // Start ollama server
  Future<bool> startOllama() async {
    try {
      await Process.start('ollama', ['serve'], mode: ProcessStartMode.detached);
      return true;
    } catch (e) {
      return false;
    }
  }

  // Stop a process by name
  Future<void> stopProcess(String name) async {
    try {
      await Process.run('pkill', ['-f', name]);
    } catch (e) {
      // Ignore
    }
  }
}