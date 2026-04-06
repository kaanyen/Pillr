bool isValidEmail(String value) {
  final v = value.trim();
  if (v.isEmpty) return false;
  return RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(v);
}

/// Minimum 8 chars, 1 number, 1 uppercase (build doc §5).
bool isValidInvitePassword(String password) {
  if (password.length < 8) return false;
  if (!RegExp(r'[0-9]').hasMatch(password)) return false;
  if (!RegExp(r'[A-Z]').hasMatch(password)) return false;
  return true;
}

String? passwordErrorMessage(String password) {
  if (password.isEmpty) return 'Password is required';
  if (password.length < 8) return 'At least 8 characters';
  if (!RegExp(r'[0-9]').hasMatch(password)) return 'Include at least one number';
  if (!RegExp(r'[A-Z]').hasMatch(password)) {
    return 'Include at least one uppercase letter';
  }
  return null;
}
