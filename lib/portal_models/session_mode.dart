/// The three lifecycle states a user's install can settle into.
///
/// * `awaiting` — first launch, verdict not yet known.
/// * `portal`   — attribution routed the user to the remote WebView.
/// * `arena`    — attribution routed the user to the native puzzle.
///
/// Once a user is sealed into `arena`, we never re-query the
/// backend — the verdict is permanent for that install.
enum SessionMode {
  awaiting,
  portal,
  arena;

  static SessionMode decode(String? raw) {
    switch (raw) {
      case 'portal':
        return SessionMode.portal;
      case 'arena':
        return SessionMode.arena;
      default:
        return SessionMode.awaiting;
    }
  }

  String encode() {
    switch (this) {
      case SessionMode.portal:
        return 'portal';
      case SessionMode.arena:
        return 'arena';
      case SessionMode.awaiting:
        return 'awaiting';
    }
  }
}
