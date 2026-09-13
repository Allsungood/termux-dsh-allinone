import 'package:flutter/material.dart';
import 'package:termux_dsh_allinone/pages/home_page.dart';
import 'package:termux_dsh_allinone/pages/setup_page.dart';
import 'package:termux_dsh_allinone/services/environment_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Check if environment is set up before launching the app
  final envService = EnvironmentService();
  final isSetupComplete = await envService.isSetupComplete();

  runApp(MyApp(isSetupComplete: isSetupComplete));
}

class MyApp extends StatelessWidget {
  final bool isSetupComplete;

  const MyApp({super.key, required this.isSetupComplete});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Termux All-in-One',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple, brightness: Brightness.dark),
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      themeMode: ThemeMode.system,
      debugShowCheckedModeBanner: false,
      home: isSetupComplete ? const HomePage() : const SetupPage(),
    );
  }
}