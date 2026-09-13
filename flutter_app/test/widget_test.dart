import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termux_dsh_allinone/models/tool_status.dart';
import 'package:termux_dsh_allinone/widgets/status_card.dart';
import 'package:termux_dsh_allinone/widgets/tool_card.dart';

Widget _host(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(width: 240, height: 360, child: child),
      ),
    ),
  );
}

void main() {
  testWidgets('installed tool offers Start and reflects the callback', (
    tester,
  ) async {
    const tool = ToolStatus(
      id: 'dsh',
      name: 'dsh',
      description: 'DeepSeek Harness — AI coding agent',
      icon: Icons.terminal,
      installed: true,
      startCommand: 'dsh web --port 3080',
      dashboardUrl: 'http://127.0.0.1:3080',
    );

    var started = false;
    await tester.pumpWidget(
      _host(
        ToolCard(
          tool: tool,
          running: false,
          onStart: () => started = true,
          onOpen: () {},
        ),
      ),
    );

    expect(find.text('dsh'), findsOneWidget);
    expect(find.text('已安装'), findsOneWidget);
    expect(find.text('启动'), findsOneWidget);

    await tester.tap(find.text('启动'));
    expect(started, isTrue);
  });

  testWidgets('optional tool that is absent offers Install', (tester) async {
    const tool = ToolStatus(
      id: 'ollama',
      name: 'Ollama',
      description: 'Local LLM inference',
      icon: Icons.memory,
      optional: true,
    );

    await tester.pumpWidget(_host(ToolCard(tool: tool, running: false)));

    expect(find.text('安装'), findsOneWidget);
    expect(find.text('未安装'), findsOneWidget);
  });

  testWidgets('running tool shows Stop', (tester) async {
    const tool = ToolStatus(
      id: 'openclaw',
      name: 'OpenClaw',
      description: 'AI gateway',
      icon: Icons.hub,
      installed: true,
      startCommand: 'openclaw gateway',
    );

    await tester.pumpWidget(_host(ToolCard(tool: tool, running: true)));

    expect(find.text('运行中'), findsOneWidget);
    expect(find.text('停止'), findsOneWidget);
  });

  testWidgets('StatusCard renders its labels', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: StatusCard(
            icon: Icons.developer_board,
            title: 'Linux runtime',
            subtitle: '6 of 6 tools ready inside the app sandbox',
          ),
        ),
      ),
    );

    expect(find.text('Linux runtime'), findsOneWidget);
    expect(find.text('6 of 6 tools ready inside the app sandbox'), findsOneWidget);
  });

  test('catalogue exposes the documented tools', () {
    final ids = ToolStatus.catalog().map((tool) => tool.id).toList();
    expect(ids, containsAll(<String>['dsh', 'openclaw', 'ollama', 'node', 'git', 'python3']));
  });
}
