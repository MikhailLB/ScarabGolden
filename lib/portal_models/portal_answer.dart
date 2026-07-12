/// Structured wrapper over the JSON reply from the router endpoint.
///
/// The backend contract:
/// ```
/// { "ok": true,  "url": "https://…", "expires": 1712345678 }   // portal
/// { "ok": false, "message": "organic" }                        // arena
/// ```
class PortalAnswer {
  final bool ok;
  final String? url;
  final String? note;
  final int? expiresAt;

  const PortalAnswer({
    required this.ok,
    this.url,
    this.note,
    this.expiresAt,
  });

  factory PortalAnswer.fromJson(Map<String, dynamic> raw) {
    return PortalAnswer(
      ok: raw['ok'] as bool? ?? false,
      url: raw['url'] as String?,
      note: raw['message'] as String?,
      expiresAt: raw['expires'] as int?,
    );
  }

  factory PortalAnswer.failure(String note) =>
      PortalAnswer(ok: false, note: note);

  bool get hasPortal => ok && (url?.isNotEmpty ?? false);
}
