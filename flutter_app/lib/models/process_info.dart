// Describes a process running in the Termux backend.
class ProcessInfo {
  final String name;
  final String displayName;
  final bool isRunning;
  final int? pid;
  final String? version;
  final String icon; // Asset path or emoji
  final String description;

  ProcessInfo({
    required this.name,
    required this.displayName,
    this.isRunning = false,
    this.pid,
    this.version,
    this.icon = 'assets/icons/terminal.png',
    this.description = '',
  });
}