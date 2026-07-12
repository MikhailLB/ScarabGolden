import 'dart:convert';

import '../env/app_facade.dart';
import '../portal_models/portal_answer.dart';
import 'aegis_store.dart';
import 'device_agent.dart';

/// Sends the assembled attribution body to the router endpoint
/// and interprets the JSON verdict.
///
/// A successful `PortalAnswer.hasPortal` result is cached to
/// secure storage so returning users can still land on the
/// WebView even if a future call fails.
class PortalPipe {
  final AegisStore store;

  PortalPipe(this.store);

  Future<PortalAnswer> query(Map<String, dynamic> body) async {
    final endpoint = AppFacade.routerEndpoint;
    if (endpoint.isEmpty) {
      return PortalAnswer.failure('no endpoint');
    }

    try {
      final uri = Uri.parse(endpoint);
      final response = await deviceAgent
          .post(
            uri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        return PortalAnswer.failure('http ${response.statusCode}');
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final answer = PortalAnswer.fromJson(decoded);

      if (answer.hasPortal) {
        await store.writePortalLink(answer.url!);
        if (answer.expiresAt != null) {
          await store.writeRemoteExpiry(answer.expiresAt!);
        }
      }
      return answer;
    } catch (err) {
      return PortalAnswer.failure(err.toString());
    }
  }

  Future<String?> cachedLink() => store.readPortalLink();
}
