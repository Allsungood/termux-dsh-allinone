import 'package:flutter/material.dart';

import 'pages/home_page.dart';
import 'pages/setup_page.dart';
import 'services/environment_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final environment = EnvironmentService();
  var ready = false;
  try {
    await environment.load();
    ready = await environment.isBootstrapped();
  } catch (_) {
    ready = false;
  }

  runApp(TermuxAllInOneApp(showSetup: !ready));
}

class TermuxAllInOneApp extends StatelessWidget {
  const TermuxAllInOneApp({super.key, required this.showSetup});

  final bool showSetup;

  static const Color _seed = Color(0xFF4F46E5);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Termux 一体化',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: _seed),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: _seed,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: showSetup ? const SetupPage() : const HomePage(),
    );
  }
}
