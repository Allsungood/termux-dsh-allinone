import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/environment_service.dart';
import '../widgets/tool_card.dart';
import 'terminal_page.dart';
import 'web_dashboard_page.dart';
import 'settings_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final envService = context.read<EnvironmentService>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Termux All-in-One'),
        elevation: 0,
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsPage()),
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          setState(() {});
        },
        child: _buildBody(),
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.refresh),
        label: const Text('Refresh'),
        onPressed: () {
          setState(() {});
        },
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _buildBody() {
    switch (_currentIndex) {
      case 0:
        return _buildToolGrid();
      case 1:
        return const TerminalPage();
      case 2:
        return const WebDashboardPage();
      default:
        return _buildToolGrid();
    }
  }

  Widget _buildToolGrid() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          const Text(
            'Tools & Services',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'One-tap access to dsh, openclaw, ollama, and more',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
          const SizedBox(height: 20),

          // Status cards
          FutureBuilder<List<Widget>>(
            future: _buildStatusCards(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              return Column(
                children: snapshot.data ?? const [],
              );
            },
          ),

          const SizedBox(height: 20),

          // Tool grid
          Expanded(
            child: FutureBuilder<List<Widget>>(
              future: _buildToolCards(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                return GridView(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    childAspectRatio: 0.85,
                  ),
                  children: snapshot.data ?? const [],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<List<Widget>> _buildStatusCards() async {
    final envService = EnvironmentService();
    final processes = await envService.getProcessStatuses();

    return processes.map((process) {
      return StatusCard(
        title: process.displayName,
        subtitle: process.isRunning ? 'Running' : 'Not installed',
        isSuccess: process.isRunning,
        icon: process.isRunning ? Icons.check_circle : Icons.error,
      );
    }).toList();
  }

  Future<List<Widget>> _buildToolCards() async {
    final envService = EnvironmentService();
    final processes = await envService.getProcessStatuses();

    return processes.map((process) {
      return ToolCard(
        process: process,
        onTap: () {
          _handleToolTap(process);
        },
      );
    }).toList();
  }

  void _handleToolTap(ProcessInfo process) {
    switch (process.name) {
      case 'dsh':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => WebDashboardPage(
              url: 'http://localhost:3080',
              title: 'dsh Web UI',
            ),
          ),
        );
        break;
      case 'openclaw':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => WebDashboardPage(
              url: 'http://localhost:18789',
              title: 'OpenClaw Dashboard',
            ),
          ),
        );
        break;
      case 'ollama':
        // Show ollama details
        _showOllamaDialog(context, process);
        break;
    }
  }

  void _showOllamaDialog(BuildContext context, ProcessInfo process) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(process.displayName),
        content: const Text('Ollama requires manual model download.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              // TODO: Implement model download
            },
            child: const Text('Download Model'),
          ),
        ],
      ),
    );
  }
}