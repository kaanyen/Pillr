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

  // Monthly letters: pastors see who and how much, admins the counts and
  // set-up. Staff have no part in the letters.
  if (starts('/settings/letters')) return role != 'pastor' && role != 'admin';

  // Health is how Pillr is running, in counts: the admin's page.
  if (starts('/health')) return role != 'admin' && role != 'pastor';

  // Overview, Settings and Help adapt to the viewer — always allowed.
  if (starts('/overview') || starts('/settings') || starts('/help')) {
    return false;
  }

  switch (role) {
    // Admin runs the workspace but has no access to financial records.
    // Fellowships is allowed for the manage tools (who belongs where);
    // ranked giving stays off that screen for this role.
    case 'admin':
      if (starts('/queue')) return true;
      if (starts('/records')) return true;
      if (starts('/entries')) return true;
      if (starts('/partners')) return true;
      if (starts('/goals')) return true;
      if (starts('/search')) return true;
      return false;

    // Staff records entries, looks up partners, and may manage fellowships
    // and Tools. No review, no config, no people management. Fellowship and
    // Tools writes go to the activity log; the Activity tab stays with admin.
    case 'staff':
      if (starts('/goals')) return true;
      // Rankings are the pastor's: staff see what they recorded, not who
      // gave the most.
      if (starts('/ranked') || starts('/leaderboard')) return true;
      if (starts('/configuration')) return true;
      if (starts('/people')) return true;
      if (starts('/activity')) return true;
      // Search is open to staff: they are the ones hunting for a partner
      // mid-service. What it returns is scoped to what they may see.
      return false;

    // Pastor sees everything except the admin audit trail.
    case 'pastor':
      if (starts('/activity')) return true;
      return false;

    default:
      return true;
  }
}
