import 'dart:async';
import 'package:flutter/material.dart';
import '../services/environment_service.dart';

class SetupPage extends StatefulWidget {
  const SetupPage({super.key});

  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> with SingleTickerProviderStateMixin {
  final EnvironmentService _envService = EnvironmentService();
  final List<String> _logs = [];
  double _progress = 0.0;
  String _currentStep = '正在准备...';
  bool _isRunning = false;
  bool _isCompleted = false;
  late AnimationController _animationController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    )..repeat(reverse: true);
    
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _addLog(String message) {
    setState(() {
      _logs.add('[${DateTime.now().toString().substring(11, 19)}] $message');
      if (_logs.length > 200) {
        _logs.removeAt(0);
      }
    });
  }

  void _updateProgress(double progress, String step) {
    setState(() {
      _progress = progress.clamp(0.0, 1.0);
      _currentStep = step;
    });
  }

  Future<void> _startSetup() async {
    if (_isRunning) return;
    
    setState(() {
      _isRunning = true;
      _progress = 0.0;
      _logs.clear();
    });

    final success = await _envService.runSetupScript(
      onProgress: (output) {
        for (final line in output.split('\n')) {
          if (line.trim().isNotEmpty) {
            _addLog(line.trim());
          }
        }
      },
      autoYes: true,
    );

    setState(() {
      _isRunning = false;
      _isCompleted = success;
      if (success) {
        _progress = 1.0;
        _currentStep = '设置完成！';
      } else {
        _currentStep = '设置失败，请查看日志';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Termux All-in-One'),
        centerTitle: true,
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              AnimatedScale(
                scale: _isRunning ? 1.0 : _pulseAnimation.value,
                duration: const Duration(milliseconds: 500),
                child: Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: _isRunning 
                        ? colorScheme.primaryContainer 
                        : colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        _isCompleted ? Icons.check_circle : Icons.terminal,
                        size: 64,
                        color: _isCompleted 
                            ? Colors.green 
                            : colorScheme.primary,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _isCompleted 
                            ? '环境已就绪'
                            : (_isRunning ? '正在配置环境...' : '欢迎使用'),
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _currentStep,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: colorScheme.onSurface.withOpacity(0.7),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Progress bar
              if (_isRunning || _isCompleted)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LinearProgressIndicator(
                      value: _progress,
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(4),
                      backgroundColor: colorScheme.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        _isCompleted ? Colors.green : colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${(_progress * 100).toInt()}%',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurface.withOpacity(0.6),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),

              const SizedBox(height: 24),

              // Action button
              if (!_isRunning && !_isCompleted)
                ElevatedButton.icon(
                  onPressed: _startSetup,
                  icon: const Icon(Icons.rocket_launch),
                  label: const Text('开始一键设置'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    textStyle: const TextStyle(fontSize: 18),
                    backgroundColor: colorScheme.primary,
                    foregroundColor: colorScheme.onPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                )
              else if (_isCompleted)
                Column(
                  children: [
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(builder: (_) => const HomePage()),
                        );
                      },
                      icon: const Icon(Icons.arrow_forward),
                      label: const Text('进入主界面'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        textStyle: const TextStyle(fontSize: 18),
                        minimumSize: const Size(double.infinity, 56),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _isCompleted = false;
                          _progress = 0.0;
                        });
                      },
                      child: const Text('重新设置'),
                    ),
                  ],
                ),

              const SizedBox(height: 24),

              // Log area
              if (_isRunning || _logs.isNotEmpty)
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              const Icon(Icons.list_alt, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                '设置日志',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const Spacer(),
                              if (_logs.isNotEmpty)
                                TextButton.icon(
                                  onPressed: () {
                                    setState(() {
                                      _logs.clear();
                                    });
                                  },
                                  icon: const Icon(Icons.clear),
                                  label: const Text('清空'),
                                ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 16),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.black87,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: ListView.builder(
                              itemCount: _logs.length,
                              reverse: true,
                              itemBuilder: (context, index) {
                                final log = _logs[_logs.length - 1 - index];
                                final isError = log.contains('❌') || log.contains('Error') || log.contains('FAILED');
                                return SelectableText(
                                  log,
                                  style: TextStyle(
                                    color: isError ? Colors.red.shade300 : Colors.green.shade300,
                                    fontFamily: 'monospace',
                                    fontSize: 11,
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),

              // Info text
              if (!_isRunning && !_isCompleted)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '将会自动配置：',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildFeatureItem('🔧 Node.js 24 LTS', '运行时环境'),
                      _buildFeatureItem('🤖 dsh (DeepSeek Harness)', 'AI 编码助手 + Web UI'),
                      _buildFeatureItem('🦞 OpenClaw', 'AI 网关 + 设备能力'),
                      _buildFeatureItem('🦙 Ollama', '本地大模型推理 CLI'),
                      _buildFeatureItem('📦 Git, Python, SSH', '开发工具链'),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureItem(String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
          const SizedBox(width: 12),
          Text(subtitle, style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6))),
        ],
      ),
    );
  }
}