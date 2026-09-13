class EnvironmentConfig {
  // dsh configuration
  final String dshWebPort;
  final String dshApprovalPolicy;
  final bool dshAutoStart;

  // OpenClaw configuration
  final int openclawPort;
  final String openclawModel;

  // Ollama configuration
  final String ollamaPort;
  final String ollamaModelsPath;

  // General settings
  final bool autoStartAtBoot;
  final bool disableBatteryOptimization;
  final bool requestPermissionsOnStartup;

  EnvironmentConfig({
    this.dshWebPort = '3080',
    this.dshApprovalPolicy = 'never',
    this.dshAutoStart = true,
    this.openclawPort = 18789,
    this.openclawModel = 'llama3.2:1b',
    this.ollamaPort = '11434',
    this.ollamaModelsPath = '',
    this.autoStartAtBoot = true,
    this.disableBatteryOptimization = true,
    this.requestPermissionsOnStartup = true,
  });

  Map<String, dynamic> toJson() => {
    'dshWebPort': dshWebPort,
    'dshApprovalPolicy': dshApprovalPolicy,
    'dshAutoStart': dshAutoStart,
    'openclawPort': openclawPort,
    'openclawModel': openclawModel,
    'ollamaPort': ollamaPort,
    'ollamaModelsPath': ollamaModelsPath,
    'autoStartAtBoot': autoStartAtBoot,
    'disableBatteryOptimization': disableBatteryOptimization,
    'requestPermissionsOnStartup': requestPermissionsOnStartup,
  };

  factory EnvironmentConfig.fromJson(Map<String, dynamic> json) {
    return EnvironmentConfig(
      dshWebPort: json['dshWebPort'] as String? ?? '3080',
      dshApprovalPolicy: json['dshApprovalPolicy'] as String? ?? 'never',
      dshAutoStart: json['dshAutoStart'] as bool? ?? true,
      openclawPort: json['openclawPort'] as int? ?? 18789,
      openclawModel: json['openclawModel'] as String? ?? 'llama3.2:1b',
      ollamaPort: json['ollamaPort'] as String? ?? '11434',
      ollamaModelsPath: json['ollamaModelsPath'] as String? ?? '',
      autoStartAtBoot: json['autoStartAtBoot'] as bool? ?? true,
      disableBatteryOptimization: json['disableBatteryOptimization'] as bool? ?? true,
      requestPermissionsOnStartup: json['requestPermissionsOnStartup'] as bool? ?? true,
    );
  }
}