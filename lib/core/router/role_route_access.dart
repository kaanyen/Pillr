/// Route access from build doc §6 (permission matrix) + Phase 1.5 shell parity.
bool isPathForbiddenForRole(String location, String role) {
  final path = location.split('?').first;

  bool starts(String p) => path == p || path.startsWith('$p/');

  // Admin: no financial / entry areas
  if (role == 'admin') {
    if (starts('/entries')) return true;
    if (starts('/partners')) return true;
    if (starts('/leaderboard')) return true;
    if (starts('/goals')) return true;
    if (starts('/arms')) return true;
    if (starts('/periods')) return true;
    return false;
  }

  // Staff: entries + dashboard + settings only (partners list deferred to Phase 2)
  if (role == 'staff') {
    if (starts('/partners')) return true;
    if (starts('/leaderboard')) return true;
    if (starts('/goals')) return true;
    if (starts('/arms')) return true;
    if (starts('/periods')) return true;
    if (starts('/users')) return true;
    if (starts('/invitations')) return true;
    if (starts('/logs')) return true;
    return false;
  }

  // Pastor: everything except admin-only logs
  if (role == 'pastor') {
    if (starts('/logs')) return true;
    return false;
  }

  return true;
}
