import 'dart:convert';

/// User-tunable settings, persisted as JSON in SharedPreferences.
class EnvironmentConfig {
  const EnvironmentConfig({
    this.dshPort = 3080,
    this.openclawPort = 18789,
    this.ollamaPort = 11434,
    this.ollamaModel = 'llama3.2:1b',
    this.keepAwake = true,
  });

  final int dshPort;
  final int openclawPort;
  final int ollamaPort;
  final String ollamaModel;
  final bool keepAwake;

  EnvironmentConfig copyWith({
    int? dshPort,
    int? openclawPort,
    int? ollamaPort,
    String? ollamaModel,
    bool? keepAwake,
  }) {
    return EnvironmentConfig(
      dshPort: dshPort ?? this.dshPort,
      openclawPort: openclawPort ?? this.openclawPort,
      ollamaPort: ollamaPort ?? this.ollamaPort,
      ollamaModel: ollamaModel ?? this.ollamaModel,
      keepAwake: keepAwake ?? this.keepAwake,
    );
  }

  Map<String, dynamic> toJson() => {
    'dshPort': dshPort,
    'openclawPort': openclawPort,
    'ollamaPort': ollamaPort,
    'ollamaModel': ollamaModel,
    'keepAwake': keepAwake,
  };

  static EnvironmentConfig fromJson(Map<String, dynamic> json) {
    return EnvironmentConfig(
      dshPort: (json['dshPort'] as num?)?.toInt() ?? 3080,
      openclawPort: (json['openclawPort'] as num?)?.toInt() ?? 18789,
      ollamaPort: (json['ollamaPort'] as num?)?.toInt() ?? 11434,
      ollamaModel: json['ollamaModel'] as String? ?? 'llama3.2:1b',
      keepAwake: json['keepAwake'] as bool? ?? true,
    );
  }

  String encode() => jsonEncode(toJson());

  static EnvironmentConfig decode(String? raw) {
    if (raw == null || raw.isEmpty) return const EnvironmentConfig();
    try {
      return EnvironmentConfig.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return const EnvironmentConfig();
    }
  }
}
