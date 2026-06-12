import 'package:cloud_functions/cloud_functions.dart';

import '../../../core/constants/firebase_constants.dart';
import '../../../core/errors/app_exception.dart';

class PlatformChurchSummary {
  PlatformChurchSummary({
    required this.churchId,
    required this.name,
    required this.isActive,
    required this.activeUsers,
    this.logoUrl,
    this.contactEmail,
    this.contactPhone,
    this.primaryContactName,
    this.address,
    this.city,
    this.region,
    this.country,
    this.currency,
    this.churchSetupCompletedAt,
    this.createdAt,
  });

  final String churchId;
  final String name;
  final bool isActive;
  final int activeUsers;
  final String? logoUrl;
  final String? contactEmail;
  final String? contactPhone;
  final String? primaryContactName;
  final String? address;
  final String? city;
  final String? region;
  final String? country;
  final String? currency;
  final dynamic churchSetupCompletedAt;
  final dynamic createdAt;
}

class PlatformRepository {
  PlatformRepository(this._functions);

  final FirebaseFunctions _functions;

  Future<List<PlatformChurchSummary>> listChurchSummaries() async {
    try {
      final callable = _functions.httpsCallable(FirebaseConstants.listChurchSummariesForPlatform);
      final res = await callable.call();
      final data = Map<String, dynamic>.from(res.data as Map);
      final raw = data['items'] as List<dynamic>? ?? [];
      return raw.map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        return PlatformChurchSummary(
          churchId: m['churchId'] as String,
          name: m['name'] as String? ?? '',
          isActive: m['isActive'] != false,
          activeUsers: (m['activeUsers'] as num?)?.toInt() ?? 0,
          logoUrl: m['logoUrl'] as String?,
          contactEmail: m['contactEmail'] as String?,
          contactPhone: m['contactPhone'] as String?,
          primaryContactName: m['primaryContactName'] as String?,
          address: m['address'] as String?,
          city: m['city'] as String?,
          region: m['region'] as String?,
          country: m['country'] as String?,
          currency: m['currency'] as String?,
          churchSetupCompletedAt: m['churchSetupCompletedAt'],
          createdAt: m['createdAt'],
        );
      }).toList();
    } on FirebaseFunctionsException catch (e) {
      throw AppException(e.message ?? 'Could not load churches.', code: e.code);
    }
  }

  Future<void> setChurchActive({required String churchId, required bool isActive}) async {
    try {
      final callable = _functions.httpsCallable(FirebaseConstants.setChurchActive);
      await callable.call(<String, dynamic>{
        'churchId': churchId,
        'isActive': isActive,
      });
    } on FirebaseFunctionsException catch (e) {
      throw AppException(e.message ?? 'Could not update church.', code: e.code);
    }
  }

  Future<void> createBootstrapInvite({required String email, required String role}) async {
    try {
      final callable = _functions.httpsCallable(FirebaseConstants.createBootstrapInvite);
      await callable.call(<String, dynamic>{
        'email': email.trim(),
        'role': role,
      });
    } on FirebaseFunctionsException catch (e) {
      throw AppException(e.message ?? 'Could not create invite.', code: e.code);
    }
  }
}
