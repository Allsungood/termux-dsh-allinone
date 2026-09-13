import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../services/web_view_service.dart';

class WebDashboardPage extends StatefulWidget {
  final String url;
  final String title;

  const WebDashboardPage({
    super.key,
    required this.url,
    required this.title,
  });

  @override
  State<WebDashboardPage> createState() => _WebDashboardPageState();
}

class _WebDashboardPageState extends State<WebDashboardPage> {
  late final WebViewController _controller;
  bool _isLoading = true;
  String _currentUrl = '';

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            // Update loading progress
          },
          onPageStarted: (String url) {
            setState(() {
              _isLoading = true;
              _currentUrl = url;
            });
          },
          onPageFinished: (String url) {
            setState(() {
              _isLoading = false;
              _currentUrl = url;
            });
          },
          onWebResourceError: (WebResourceError error) {
            // Handle error
          },
          onNavigationRequest: (NavigationRequest request) {
            // Allow navigation to http/https URLs
            if (request.url.startsWith('http://') ||
                request.url.startsWith('https://')) {
              return NavigationDecision.navigate;
            }
            // For other schemes (like intent), allow them
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _controller.reload();
            },
          ),
          IconButton(
            icon: const Icon(Icons.open_in_browser),
            onPressed: () async {
              // Open in external browser
              await launchUrl(Uri.parse(_currentUrl));
            },
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'zoom_in':
                  _controller.setZoomLevel(_controller.value.zoomLevel + 0.25);
                  break;
                case 'zoom_out':
                  _controller.setZoomLevel(_controller.value.zoomLevel - 0.25);
                  break;
                case 'reset_zoom':
                  _controller.setZoomLevel(1.0);
                  break;
              }
            },
            itemBuilder: (BuildContext context) => [
              const PopupMenuItem(
                value: 'zoom_in',
                child: Text('放大'),
              ),
              const PopupMenuItem(
                value: 'zoom_out',
                child: Text('缩小'),
              ),
              const PopupMenuItem(
                value: 'reset_zoom',
                child: Text('重置缩放'),
              ),
            ],
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            Container(
              color: Colors.black54,
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
        ],
      ),
      floatingActionButton: _isLoading
          ? null
          : FloatingActionButton(
              onPressed: () {
                _controller.goBackOrForward(0); // Go to top
              },
              child: const Icon(Icons.arrow_upward),
              mini: true,
            ),
    );
  }
}