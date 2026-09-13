import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter/foundation.dart';

class WebViewService {
  WebViewService._();
  static final WebViewService _instance = WebViewService._();
  factory WebViewService() => _instance;

  final Map<int, String> _webViews = {};
  int _nextId = 0;

  // Create a new WebView instance and return its ID
  int createWebView(String url, {bool javaScriptEnabled = true}) {
    final id = _nextId++;
    _webViews[id] = url;
    return id;
  }

  // Get the URL for a WebView ID
  String? getUrl(int id) => _webViews[id];

  // Update URL for a WebView ID
  void updateUrl(int id, String url) {
    if (_webViews.containsKey(id)) {
      _webViews[id] = url;
    }
  }

  // Remove a WebView
  void disposeWebView(int id) {
    _webViews.remove(id);
  }

  // Get all active WebView IDs
  List<int> getWebViewIds() => _webViews.keys.toList();

  // Generate WebView controller configuration
  WebViewController getControllerConfig(int id, {Function(WebViewController)? onPageFinished}) {
    final controller = WebViewController()
      ..setJavaScriptMode(javaScriptEnabled: JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            debugPrint('Page started: $url');
          },
          onPageFinished: (url) {
            debugPrint('Page finished: $url');
            if (onPageFinished != null) {
              onPageFinished(controller);
            }
          },
          onWebResourceError: (error) {
            debugPrint('WebView error: ${error.description}');
          },
        ),
      )
      ..loadRequest(Uri.parse(_webViews[id] ?? 'about:blank'));

    return controller;
  }
}