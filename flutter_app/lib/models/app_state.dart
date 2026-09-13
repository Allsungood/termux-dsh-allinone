import 'package:riverpod/riverpod.dart';
import 'environment_config.dart';
import 'process_info.dart';

// --- App State Management ---
class AppState {
  final EnvironmentConfig? environmentConfig;
  final List<ProcessInfo> activeProcesses;
  final bool isLoading;
  final String? errorMessage;

  AppState({
    this.environmentConfig,
    this.activeProcesses = const [],
    this.isLoading = false,
    this.errorMessage,
  });

  AppState copyWith({
    EnvironmentConfig? environmentConfig,
    List<ProcessInfo>? activeProcesses,
    bool? isLoading,
    String? errorMessage,
  }) {
    return AppState(
      environmentConfig: environmentConfig ?? this.environmentConfig,
      activeProcesses: activeProcesses ?? this.activeProcesses,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

// --- State Notifier ---
class AppStateNotifier extends StateNotifier<AppState> {
  AppStateNotifier() : super(const AppState());

  void setLoading(bool loading) {
    state = state.copyWith(isLoading: loading);
  }

  void setError(String? error) {
    state = state.copyWith(errorMessage: error);
  }

  void clearError() {
    state = state.copyWith(errorMessage: null);
  }
}

final appStateNotifierProvider = StateNotifierProvider<AppStateNotifier, AppState>((ref) {
  return AppStateNotifier();
});