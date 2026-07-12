import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../core/aegis_store.dart';
import '../core/device_agent.dart';
import '../core/herald_pipe.dart';
import '../core/net_sensor.dart';
import 'tempest_stage.dart';

// A no-op pre-warm entry point kept for parity with the boot
// stage's `deferred` import.  Extended later if we ever need to
// pre-initialise Chromium.
Future<void> warmPortalEngine() async {}

/// Full-screen WebView shell — the "gray" experience.
///
/// Wires up:
///   * Real-device User-Agent (with `appid`/`appname` suffix).
///   * Third-party cookies + video autoplay on Android.
///   * File upload via file_picker.
///   * Debounced connectivity → TempestStage.
///   * DNS/disconnect codes → immediate loader overlay so the
///     Chromium error page is never visible.
///   * Redirect-loop retry (up to 3 tries) before giving up.
///   * Safe-area kill CSS + keyboard-scroll JS.
class PortalStage extends StatefulWidget {
  final String url;
  final AegisStore store;
  final HeraldPipe herald;
  final NetSensor sensor;

  const PortalStage({
    super.key,
    required this.url,
    required this.store,
    required this.herald,
    required this.sensor,
  });

  @override
  State<PortalStage> createState() => _PortalStageState();
}

class _PortalStageState extends State<PortalStage>
    with WidgetsBindingObserver {
  late final WebViewController _web;
  bool _spinning = true;
  bool _errored = false;
  bool _routingToTempest = false;

  String? _lastMainFrameUrl;
  int _redirectRetries = 0;

  StreamSubscription<List<ConnectivityResult>>? _connSub;
  Timer? _offlineDebounce;

  void Function(String)? _previousHeraldHandler;

  void _lockImmersive() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _lockImmersive();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _lockImmersive();

    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(deviceAgent.userAgent)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) {
          if (!mounted) return;
          setState(() {
            _errored = false;
            _spinning = true;
          });
        },
        onPageFinished: (_) {
          if (!mounted) return;
          // Pitfall §4 — if we already latched an error, keep
          // the spinner overlay in place so the native Chromium
          // "no internet" glyph never bleeds through.
          if (_errored) return;
          setState(() => _spinning = false);
          _redirectRetries = 0;
          _injectSafeAreaKill();
          _injectKeyboardScrollFix();
          _pokeVideoAutoplay();
        },
        onWebResourceError: _handleWebError,
        onHttpError: (_) {},
        onNavigationRequest: (request) {
          final uri = Uri.tryParse(request.url);
          if (uri == null) return NavigationDecision.prevent;
          final scheme = uri.scheme;
          if (scheme == 'http' ||
              scheme == 'https' ||
              scheme == 'about' ||
              scheme == 'data' ||
              scheme == 'blob') {
            if (request.isMainFrame) _lastMainFrameUrl = request.url;
            return NavigationDecision.navigate;
          }
          _openExternal(uri);
          return NavigationDecision.prevent;
        },
      ))
      ..enableZoom(false);

    _configureAndroidWebView();
    _web.loadRequest(Uri.parse(widget.url));

    _previousHeraldHandler = widget.herald.onFreshLink;
    widget.herald.onFreshLink = (url) {
      if (!mounted) return;
      _web.loadRequest(Uri.parse(url));
    };

    _connSub = widget.sensor.pulse.listen(_onConnectivity);
  }

  void _handleWebError(WebResourceError err) {
    // §4 pitfall — some webview_flutter builds return null for
    // isForMainFrame.  Only bail on an EXPLICIT sub-frame value.
    if (err.isForMainFrame == false) return;

    final desc = err.description.toLowerCase();

    // Redirect loop → replay the last known good main-frame URL
    // up to 3 times before we give up and route offline.
    final loopy = desc.contains('too_many_redirects') ||
        desc.contains('too many redirects') ||
        err.errorCode == -1007 ||
        err.errorCode == -9;
    if (loopy && _lastMainFrameUrl != null && _redirectRetries < 3) {
      _redirectRetries++;
      _web.loadRequest(Uri.parse(_lastMainFrameUrl!));
      return;
    }

    if (mounted) {
      setState(() {
        _errored = true;
        _spinning = true;
      });
    }

    final dnsOrDrop = desc.contains('name_not_resolved') ||
        desc.contains('err_name_not_resolved') ||
        desc.contains('internet_disconnected') ||
        desc.contains('network_changed') ||
        desc.contains('address_unreachable') ||
        desc.contains('connection_refused') ||
        desc.contains('connection_reset') ||
        desc.contains('connection_timed_out') ||
        err.errorCode == -2 ||
        err.errorCode == -6 ||
        err.errorCode == -7 ||
        err.errorCode == -21 ||
        err.errorCode == -105 ||
        err.errorCode == -106 ||
        err.errorCode == -109 ||
        err.errorCode == -118;

    if (dnsOrDrop) {
      _routeTempest(directly: true);
    } else {
      _routeTempest(directly: false);
    }
  }

  void _onConnectivity(List<ConnectivityResult> results) {
    final none = results.every((r) => r == ConnectivityResult.none);
    if (!none) {
      _offlineDebounce?.cancel();
      return;
    }
    // §3 pitfall — debounce so brief VPN toggles do not flash
    // the tempest screen on a healthy connection.
    _offlineDebounce?.cancel();
    _offlineDebounce = Timer(const Duration(milliseconds: 700), () {
      _routeTempest(directly: false);
    });
  }

  Future<void> _routeTempest({required bool directly}) async {
    if (_routingToTempest || !mounted) return;
    if (!directly) {
      final live = await widget.sensor.hasReachability();
      if (live || !mounted) return;
    }
    _routingToTempest = true;
    final currentUrl = await _web.currentUrl() ?? widget.url;
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => TempestStage(
          retryBuilder: (_) => PortalStage(
            url: currentUrl,
            store: widget.store,
            herald: widget.herald,
            sensor: widget.sensor,
          ),
        ),
      ),
    );
  }

  void _configureAndroidWebView() {
    if (!Platform.isAndroid) return;
    if (_web.platform is! AndroidWebViewController) return;

    final android = _web.platform as AndroidWebViewController;
    android.setMediaPlaybackRequiresUserGesture(false);
    android.setOnShowFileSelector(_pickForWebView);

    final cookies = AndroidWebViewCookieManager(
      AndroidWebViewCookieManagerCreationParams
          .fromPlatformWebViewCookieManagerCreationParams(
        const PlatformWebViewCookieManagerCreationParams(),
      ),
    );
    cookies.setAcceptThirdPartyCookies(android, true);
  }

  Future<List<String>> _pickForWebView(FileSelectorParams params) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: params.mode == FileSelectorMode.openMultiple,
        type: FileType.any,
      );
      if (result == null) return const <String>[];
      return result.files
          .where((f) => f.path != null)
          .map((f) => Uri.file(f.path!).toString())
          .toList();
    } catch (_) {
      return const <String>[];
    }
  }

  void _pokeVideoAutoplay() {
    _web.runJavaScript('''
(function(){
  try {
    document.querySelectorAll('video').forEach(function(v){
      v.muted = true; v.defaultMuted = true;
      v.setAttribute('playsinline','');
      var p = v.play();
      if (p && p.catch) p.catch(function(){});
    });
  } catch(e) {}
})();
''');
  }

  void _injectKeyboardScrollFix() {
    _web.runJavaScript('''
(function(){
  if (window.__sgKbFix) return;
  window.__sgKbFix = true;

  function isField(el){
    return el && (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA' || el.isContentEditable);
  }
  function nudge(){
    var el = document.activeElement;
    if (!isField(el)) return;
    try {
      el.scrollIntoView({ behavior: 'auto', block: 'nearest' });
    } catch(e) {}
  }

  document.addEventListener('focusin', function(e){
    if (isField(e.target)) setTimeout(nudge, 350);
  });

  if (window.visualViewport){
    var prev = window.visualViewport.height;
    window.visualViewport.addEventListener('resize', function(){
      var h = window.visualViewport.height;
      if (h < prev) setTimeout(nudge, 120);
      prev = h;
    });
  }
})();
''');
  }

  void _injectSafeAreaKill() {
    _web.runJavaScript(r'''
(function(){
  if (window.__sgSafeAreaLoop) return;
  window.__sgSafeAreaLoop = true;

  var TAG = '__sgSafeAreaSheet';
  var CSS =
    ':root{' +
      '--safe-area-inset-top:0px!important;' +
      '--safe-area-inset-right:0px!important;' +
      '--safe-area-inset-bottom:0px!important;' +
      '--safe-area-inset-left:0px!important;' +
      '--sat:0px!important;--sar:0px!important;' +
      '--sab:0px!important;--sal:0px!important;' +
      '--safe-top:0px!important;--safe-right:0px!important;' +
      '--safe-bottom:0px!important;--safe-left:0px!important;' +
    '}';

  function keyboardOpen(){
    if (!window.visualViewport) return false;
    return window.visualViewport.height < window.innerHeight * 0.75;
  }

  function apply(){
    if (keyboardOpen()) return;
    var head = document.head || document.documentElement;
    if (!head) return;
    var m = document.querySelector('meta[name="viewport"]');
    if (m && !/viewport-fit\s*=\s*contain/i.test(m.getAttribute('content') || '')) {
      var c = (m.getAttribute('content') || '')
        .replace(/,?\s*viewport-fit\s*=\s*\w+/ig, '').trim();
      m.setAttribute('content', c + (c ? ', ' : '') + 'viewport-fit=contain');
    }
    var s = document.getElementById(TAG);
    if (!s){ s = document.createElement('style'); s.id = TAG; head.appendChild(s); }
    if (s.textContent !== CSS) s.textContent = CSS;
    if (head.lastElementChild !== s) head.appendChild(s);
  }

  apply();
  ['pushState','replaceState'].forEach(function(fn){
    var orig = history[fn];
    history[fn] = function(){
      var r = orig.apply(this, arguments);
      setTimeout(apply, 80);
      setTimeout(apply, 400);
      return r;
    };
  });
  window.addEventListener('popstate', function(){ setTimeout(apply, 80); });
  setInterval(apply, 2500);
})();
''');
  }

  Future<void> _openExternal(Uri uri) async {
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connSub?.cancel();
    _offlineDebounce?.cancel();
    // §12 pitfall — restore the previous herald handler rather
    // than nulling it, so subsequent warm push taps still route.
    widget.herald.onFreshLink = _previousHeraldHandler;
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
    ]);
    super.dispose();
  }

  Future<bool> _handleBack() async {
    if (await _web.canGoBack()) {
      await _web.goBack();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final landscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final vp = MediaQuery.of(context).viewPadding;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) await _handleBack();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        resizeToAvoidBottomInset: false,
        body: Stack(
          fit: StackFit.expand,
          children: [
            Padding(
              padding: landscape
                  ? EdgeInsets.only(left: vp.left, right: vp.right)
                  : EdgeInsets.only(top: vp.top),
              child: WebViewWidget(controller: _web),
            ),
            if (_spinning)
              const Positioned.fill(
                child: ColoredBox(
                  color: Colors.black,
                  child: Center(
                    child: CircularProgressIndicator(
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Color(0xFFEED27B)),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
