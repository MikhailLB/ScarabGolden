import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../bridge/insight.dart';
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

  // Clarity funnel state.  `_offerReached` flips once the first
  // main-frame page finishes without an error — used to decide
  // whether a subsequent web_error is `web_offer_unreachable`
  // (never saw the offer at all) or `web_error_after_load`.
  // `_pageHadError` is reset per navigation to keep the flag
  // honest on SPA route changes.
  bool _offerReached = false;
  bool _pageHadError = false;

  StreamSubscription<List<ConnectivityResult>>? _connSub;
  Timer? _offlineDebounce;

  void Function(String)? _previousHeraldHandler;

  static final RegExp _depositRx = RegExp(
    r'(deposit|cashier|top.?up|replenish|payment|checkout|wallet|пополн|депозит|касс|оплат|внести|платеж)',
    caseSensitive: false,
  );
  static final RegExp _registerRx = RegExp(
    r'(sign.?up|regist|create.?account|onboarding|регистрац|зарегистр)',
    caseSensitive: false,
  );
  static final RegExp _loginRx = RegExp(
    r'(sign.?in|log.?in|log.?on|/auth\b|authoriz|войти|вход|авториз)',
    caseSensitive: false,
  );

  void _lockImmersive() {
    // Keep the nav bar *always drawn* (transparent) instead of
    // toggling it in/out with `immersiveSticky`.  Immersive-sticky
    // forces Android to re-inject the 3-button bar the moment an
    // <input> gains focus — the WebView then relayouts under the
    // new viewport height and visibly jumps.  With `manual` +
    // [SystemUiOverlay.bottom] the bar's geometry is constant, so
    // the IME open/close cannot punch a layout jump into the page.
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: const [SystemUiOverlay.bottom],
    );
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
      systemNavigationBarContrastEnforced: false,
      statusBarColor: Colors.transparent,
    ));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _lockImmersive();
      Insight.event('web_foreground');
    } else if (state == AppLifecycleState.paused) {
      // Paused inside the WebView is the single cleanest drop-off
      // marker — combine with `last_screen` to slice the funnel.
      Insight.event('web_background');
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Insight.screen('web');
    Insight.event('web_open');

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
      ..addJavaScriptChannel(
        'AegisInsight',
        onMessageReceived: (m) => _onWebSignal(m.message),
      )
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) {
          if (!mounted) return;
          // Reset the per-navigation error flag so that a healthy
          // SPA route flip does not stay poisoned by a stale
          // failure from the previous page.
          _pageHadError = false;
          setState(() {
            _errored = false;
            _spinning = true;
          });
        },
        onPageFinished: (url) {
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
          _installInsightProbe();
          _trackWebPage(url);
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
          Insight.event('web_external');
          Insight.tag('web_external_scheme', scheme);
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
    _pageHadError = true;

    final desc = err.description.toLowerCase();

    // Report the failure into Clarity BEFORE we branch on it, so
    // even a recoverable redirect loop leaves a breadcrumb in the
    // funnel.  The reason string is a coarse classification —
    // full text lives in `web_last_error`.
    final String reason = _classifyWebError(err);
    final String failedUrl = _lastMainFrameUrl ?? widget.url;
    final String host = Uri.tryParse(failedUrl)?.host ?? '';
    Insight.event('web_error');
    Insight.tag('web_error_reason', reason);
    Insight.tag('web_last_error', '${err.errorCode}:${err.description}');
    if (host.isNotEmpty) Insight.tag('web_error_host', host);
    if (!_offerReached) {
      Insight.event('web_offer_unreachable');
      Insight.tag('offer_reached', 'false');
      Insight.tag('offer_unreachable_reason', reason);
    } else {
      Insight.event('web_error_after_load');
    }

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

  // ─────────────────────────────────────────────────────────
  // Clarity / Insight — web funnel wiring
  // ─────────────────────────────────────────────────────────

  /// Coarse classification of a WebResourceError into one of a
  /// short set of stable reasons.  Full text lives in a tag so
  /// event names stay low-cardinality.
  static String _classifyWebError(WebResourceError err) {
    final String d = err.description.toLowerCase();
    final int c = err.errorCode;
    if (d.contains('connection_refused') ||
        d.contains('connection refused')) {
      return 'connection_refused';
    }
    if (d.contains('too_many_redirects') ||
        d.contains('too many redirects')) {
      return 'redirect_loop';
    }
    if (d.contains('name_not_resolved') ||
        d.contains('address_unreachable') ||
        d.contains('unknownhost') ||
        c == -2) {
      return 'dns_unresolved';
    }
    if (d.contains('timed out') || d.contains('timeout') || c == -8) {
      return 'timeout';
    }
    if (d.contains('internet_disconnected') ||
        d.contains('network_changed') ||
        c == -6) {
      return 'no_network';
    }
    if (d.contains('connection_reset')) return 'connection_reset';
    if (d.contains('connection_closed') || d.contains('empty_response')) {
      return 'connection_closed';
    }
    if (d.contains('ssl') || d.contains('cert') || c == -11) {
      return 'ssl_error';
    }
    if (d.contains('blocked')) return 'blocked';
    return 'other';
  }

  /// Called on every successful `onPageFinished`.  Sets the
  /// per-URL screen label, latches `offer_reached=true` on the
  /// very first non-errored page, and tags register/login/cashier
  /// hits via URL regex.
  void _trackWebPage(String url) {
    final Uri? uri = Uri.tryParse(url);
    final String label =
        uri == null ? url : '${uri.host}${uri.path}';
    Insight.screenName('web:$label');
    Insight.event('web_page');
    Insight.tag('web_last_url', url);
    if (!_offerReached && !_pageHadError) {
      _offerReached = true;
      Insight.event('web_offer_reached');
      Insight.tag('offer_reached', 'true');
      if (uri?.host != null && uri!.host.isNotEmpty) {
        Insight.tag('offer_host', uri.host);
      }
    }
    if (_depositRx.hasMatch(url)) {
      Insight.event('web_cashier_page');
      Insight.tag('reached_cashier', 'true');
    }
    _trackAuthPage(url);
  }

  void _trackAuthPage(String url) {
    if (_registerRx.hasMatch(url)) {
      Insight.event('web_register_page');
      Insight.tag('reached_register', 'true');
    } else if (_loginRx.hasMatch(url)) {
      Insight.event('web_login_page');
      Insight.tag('reached_login', 'true');
    }
  }

  /// Idempotent JS probe (guarded by `window.__aegisInsight`) that
  /// bridges SPA route changes, deposit/register/login clicks and
  /// auth form submits over the `AegisInsight` JavaScriptChannel.
  /// The DOM inside the WebView is invisible to Clarity replay,
  /// so this is the only way to see the in-page funnel.
  void _installInsightProbe() {
    _web.runJavaScript(r'''
(function(){
  if (window.__aegisInsight) return; window.__aegisInsight = true;
  function send(t){ try { AegisInsight.postMessage(t); } catch(e){} }
  var DEP=/(deposit|cashier|top.?up|add funds|replenish|payment|pay now|checkout|withdraw|пополн|депозит|касс|оплат|внести|вывод|платеж)/i;
  var REG=/(sign.?up|regist|create.?account|регистрац|зарегистр)/i;
  var LOG=/(sign.?in|log.?in|log.?on|войти|вход|авториз)/i;
  var lastPath='';
  function reportPath(){ var p=location.pathname+location.search; if(p!==lastPath){ lastPath=p; send('path:'+p);} }
  reportPath();
  ['pushState','replaceState'].forEach(function(fn){ var o=history[fn]; history[fn]=function(){ var r=o.apply(this,arguments); setTimeout(reportPath,60); return r; }; });
  window.addEventListener('popstate',function(){ setTimeout(reportPath,60); });
  document.addEventListener('click',function(e){
    try{ var el=e.target;
      for(var i=0;i<4&&el;i++){
        var t=((el.innerText||el.value||(el.getAttribute&&el.getAttribute('aria-label'))||'')+'').trim();
        if(t){ if(DEP.test(t)){send('deposit_click:'+t.slice(0,60));return;}
               if(REG.test(t)){send('register_click:'+t.slice(0,60));return;}
               if(LOG.test(t)){send('login_click:'+t.slice(0,60));return;} }
        el=el.parentElement;
      }
    }catch(x){}
  },true);
  document.addEventListener('submit',function(e){
    try{ var f=e.target;
      var pw=f.querySelectorAll?f.querySelectorAll('input[type="password"]'):[];
      var blob=((f.innerText||'')+' '+(f.getAttribute('action')||'')+' '+(f.className||''));
      var confirm=f.querySelector&&(f.querySelector('input[name*="confirm" i]')||f.querySelector('input[name*="repeat" i]'));
      if(pw&&pw.length>=2){send('auth_submit:register');return;}
      if(pw&&pw.length===1){ send('auth_submit:'+((confirm||REG.test(blob))?'register':'login')); return; }
      if(REG.test(blob)){send('auth_submit:register');return;}
      if(LOG.test(blob)){send('auth_submit:login');return;}
      send('form_submit');
    }catch(x){ send('form_submit'); }
  },true);
})();
''');
  }

  void _onWebSignal(String raw) {
    final int i = raw.indexOf(':');
    final String type = i < 0 ? raw : raw.substring(0, i);
    final String data = i < 0 ? '' : raw.substring(i + 1);
    switch (type) {
      case 'path':
        Insight.event('web_spa_route');
        Insight.tag('web_last_path', data);
        if (_depositRx.hasMatch(data)) {
          Insight.event('web_cashier_page');
          Insight.tag('reached_cashier', 'true');
        }
        _trackAuthPage(data);
        break;
      case 'deposit_click':
        Insight.event('web_deposit_click');
        Insight.tag('deposit_intent', 'true');
        if (data.isNotEmpty) Insight.tag('deposit_label', data);
        break;
      case 'register_click':
        Insight.event('web_register_click');
        Insight.tag('register_intent', 'true');
        break;
      case 'login_click':
        Insight.event('web_login_click');
        Insight.tag('login_intent', 'true');
        break;
      case 'auth_submit':
        if (data == 'register') {
          Insight.event('web_register_submit');
          Insight.tag('attempted_register', 'true');
        } else {
          Insight.event('web_login_submit');
          Insight.tag('attempted_login', 'true');
        }
        break;
      case 'form_submit':
        Insight.event('web_form_submit');
        break;
    }
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
    // NOTE: intentionally do NOT re-lock orientation here.
    // dispose() runs AFTER the next route's initState has already
    // applied its own preference (e.g. TempestStage unlocks all
    // four orientations) — clobbering that here would silently
    // re-lock the No-Wi-Fi screen to portrait.  The arena
    // LoadingScreen locks portrait itself on entry.
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
    // `viewPaddingOf` returns the raw system-bar insets *without*
    // subtracting the IME height, so this padding stays constant
    // when the keyboard opens.  That's the whole trick that stops
    // the WebView from jumping on 3-button navigation devices —
    // the nav-bar area is reserved once, the IME opens on top,
    // and no relayout of the page happens.
    final vp = MediaQuery.viewPaddingOf(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) await _handleBack();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        // Must stay false — Scaffold's default IME resize would
        // undo the whole point of the fix above.
        resizeToAvoidBottomInset: false,
        body: Stack(
          fit: StackFit.expand,
          children: [
            Padding(
              padding: vp,
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
