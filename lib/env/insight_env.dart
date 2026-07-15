// Microsoft Clarity project id — one per app per store submission.
//
// `[FINGERPRINT]` per gray-flow playbook: never reuse a Clarity
// project id across apps.  The dashboard is sliced by id, so
// duplicating it would collapse two apps' funnels into one and
// also give Clarity a stable string to fingerprint on across
// binaries in a suspicious way.
const String kClarityProjectId = 'xmtaxt3t6f';
