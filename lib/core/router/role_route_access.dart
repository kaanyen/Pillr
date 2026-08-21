/// Route access per role (build doc §6 permission matrix).
///
/// Rewritten for the consolidated information architecture. The permissions
/// themselves are unchanged — only the paths they guard. Note that several
/// merged screens are readable by more roles than their predecessors were,
/// because the screen now adapts its content: Queue shows a staff member only
/// their own entries and no review actions, so it is safe for them to open,
/// where the old `/approvals` was not.
bool isPathForbiddenForRole(String location, String role) {
  final path = location.split('?').first;

  bool starts(String p) => path == p || path.startsWith('$p/');

  // Overview, Settings and Help adapt to the viewer — always allowed.
  if (starts('/overview') || starts('/settings') || starts('/help')) return false;

  switch (role) {
    // Admin runs the workspace but has no access to financial records.
    case 'admin':
      if (starts('/queue')) return true;
      if (starts('/records')) return true;
      if (starts('/entries')) return true;
      if (starts('/partners')) return true;
      if (starts('/goals')) return true;
      if (starts('/search')) return true;
      return false;

    // Staff records entries and looks up partners. No review, no config,
    // no people management, no audit trail.
    case 'staff':
      if (starts('/goals')) return true;
      if (starts('/configuration')) return true;
      if (starts('/people')) return true;
      if (starts('/activity')) return true;
      if (starts('/search')) return true;
      return false;

    // Pastor sees everything except the admin audit trail.
    case 'pastor':
      if (starts('/activity')) return true;
      return false;

    default:
      return true;
  }
}
