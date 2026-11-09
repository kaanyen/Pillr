/// Cloud Function names (must match `functions/src/index.ts`).
class FirebaseConstants {
  FirebaseConstants._();

  static const validateInviteCode = 'validateInviteCode';
  static const validateBootstrapInvite = 'validateBootstrapInvite';
  static const completeRegistration = 'completeRegistration';
  static const redeemBootstrapInvite = 'redeemBootstrapInvite';
  static const createBootstrapInvite = 'createBootstrapInvite';
  static const listChurchSummariesForPlatform = 'listChurchSummariesForPlatform';
  static const setChurchActive = 'setChurchActive';
  static const generateInviteCode = 'generateInviteCode';
  static const activatePeriod = 'activatePeriod';
  static const updateChurchMember = 'updateChurchMember';
  static const previewMonthlyPartnerGivingEmail =
      'previewMonthlyPartnerGivingEmail';
  static const runMonthlyPartnerGivingSummary =
      'runMonthlyPartnerGivingSummary';
  static const fellowshipChange = 'fellowshipChange';
  static const partnerMerge = 'partnerMerge';
  static const partnerUnmerge = 'partnerUnmerge';
  static const undoOperation = 'undoOperation';
  static const findSimilarEntries = 'findSimilarEntries';
  static const churchHealth = 'churchHealth';
  static const remindPastors = 'remindPastors';
  static const startBackup = 'startBackup';
  static const listBackups = 'listBackups';
  static const testApprovalMessage = 'testApprovalMessage';
  static const fellowshipRhythmCounts = 'fellowshipRhythmCounts';
}
