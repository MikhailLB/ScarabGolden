import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../theme.dart';

class WebPageScreen extends StatefulWidget {
  final String title;
  final String url;

  const WebPageScreen({
    super.key,
    required this.title,
    required this.url,
  });

  @override
  State<WebPageScreen> createState() => _WebPageScreenState();
}

class _WebPageScreenState extends State<WebPageScreen> {
  late final WebViewController _controller;
  bool _loading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _loading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (err) {
            if (mounted) {
              setState(() {
                _hasError = true;
                _loading = false;
              });
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
        surfaceTintColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.black),
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.white,
          statusBarIconBrightness: Brightness.dark,
        ),
        title: Text(
          widget.title,
          style: const TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: Stack(
        children: [
          if (!_hasError)
            Container(
              color: Colors.white,
              child: WebViewWidget(controller: _controller),
            )
          else
            _NoConnection(onRetry: () {
              setState(() {
                _hasError = false;
                _loading = true;
              });
              _controller.loadRequest(Uri.parse(widget.url));
            }),
          if (_loading && !_hasError)
            const Center(
              child: CircularProgressIndicator(color: Colors.black),
            ),
        ],
      ),
    );
  }
}

class _NoConnection extends StatelessWidget {
  final VoidCallback onRetry;
  const _NoConnection({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final isPortrait = MediaQuery.of(context).size.height >=
        MediaQuery.of(context).size.width;
    final asset = isPortrait
        ? 'assets/nowifi/nowifi_vert.webp'
        : 'assets/nowifi/nowifi_hor.webp';
    return Stack(
      children: [
        Positioned.fill(
          child: Image.asset(asset, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  Container(color: AppColors.darkNavy)),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 40,
          child: Center(
            child: ElevatedButton(
              onPressed: onRetry,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: AppColors.darkNavy,
                padding: const EdgeInsets.symmetric(
                    horizontal: 32, vertical: 12),
              ),
              child: const Text(
                'RETRY',
                style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
