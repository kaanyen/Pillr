class InviteValidationResult {
  InviteValidationResult({
    required this.valid,
    this.churchName,
    this.churchId,
    this.role,
    this.codeId,
    this.errorMessage,
  });

  final bool valid;
  final String? churchName;
  final String? churchId;
  final String? role;
  final String? codeId;
  final String? errorMessage;
}

class InviteRecord {
  InviteRecord({
    required this.id,
    required this.code,
    required this.email,
    required this.role,
    required this.createdBy,
    required this.createdAt,
    required this.expiresAt,
    required this.status,
    this.createdByName,
  });

  final String id;
  final String code;
  final String email;
  final String role;
  final String createdBy;
  final DateTime createdAt;
  final DateTime expiresAt;
  final String status;
  final String? createdByName;
}
