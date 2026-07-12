import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';

/// Wraps `connectivity_plus` with two upgrades from the
/// pitfalls guide:
///
///   1. VPN / bluetooth / other interfaces are treated as
///      **valid** connectivity — otherwise the No-Wi-Fi screen
///      flashes on/off every time the user toggles a tunnel.
///   2. The DNS probe timeout is 7 seconds (was 3 s in the
///      naïve template).  Genuinely-offline devices raise a
///      `SocketException` instantly, so widening the timeout
///      only helps the slow-tunnel case.
class NetSensor {
  static const Set<ConnectivityResult> _valid = <ConnectivityResult>{
    ConnectivityResult.wifi,
    ConnectivityResult.mobile,
    ConnectivityResult.ethernet,
    ConnectivityResult.vpn,
    ConnectivityResult.bluetooth,
    ConnectivityResult.other,
  };

  final Connectivity _plugin = Connectivity();

  Future<bool> hasReachability() async {
    final results = await _plugin.checkConnectivity();
    if (!results.any(_valid.contains)) return false;
    try {
      final probe = await InternetAddress.lookup('one.one.one.one')
          .timeout(const Duration(seconds: 7));
      return probe.isNotEmpty && probe.first.rawAddress.isNotEmpty;
    } on SocketException {
      return false;
    } catch (_) {
      return false;
    }
  }

  Stream<List<ConnectivityResult>> get pulse =>
      _plugin.onConnectivityChanged;
}
