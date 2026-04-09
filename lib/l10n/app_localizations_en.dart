// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Pillr';

  @override
  String get navSectionMain => 'MAIN';

  @override
  String get navSectionAdmin => 'ADMIN';

  @override
  String get navSectionPartnership => 'PARTNERSHIP';

  @override
  String get navSectionConfiguration => 'CONFIGURATION';

  @override
  String get navDashboard => 'Dashboard';

  @override
  String get navUsers => 'Users';

  @override
  String get navInvitations => 'Invitations';

  @override
  String get navActivityLogs => 'Activity logs';

  @override
  String get navSettings => 'Settings';

  @override
  String get navEntries => 'Entries';

  @override
  String get navApprovals => 'Approvals';

  @override
  String get navPartners => 'Partners';

  @override
  String get navLeaderboard => 'Leaderboard';

  @override
  String get navGoals => 'Goals';

  @override
  String get navPartnershipArms => 'Partnership arms';

  @override
  String get navPeriods => 'Periods';

  @override
  String get navHelp => 'Help';

  @override
  String get titleDashboard => 'Dashboard';

  @override
  String get titleApprovals => 'Approvals';

  @override
  String get titleEntries => 'Entries';

  @override
  String get titleMyEntries => 'My entries';

  @override
  String get titleEntrySubmitted => 'Entry submitted';

  @override
  String get titlePartners => 'Partners';

  @override
  String get titleLeaderboard => 'Leaderboard';

  @override
  String get titleGoals => 'Goals';

  @override
  String get titleArms => 'Partnership arms';

  @override
  String get titlePeriods => 'Periods';

  @override
  String get titleUsers => 'Users';

  @override
  String get titleInvitations => 'Invitations';

  @override
  String get titleActivityLogs => 'Activity logs';

  @override
  String get titleSettings => 'Settings';

  @override
  String get titleSearch => 'Search';

  @override
  String get titleNotifications => 'Notifications';

  @override
  String get titleHelp => 'How partnership recording works';

  @override
  String get titleBulkImport => 'Bulk import';

  @override
  String get searchHint => 'Search church data (partners, entries)…';

  @override
  String get toolbarNotifications => 'Notifications';

  @override
  String get toolbarHelp => 'Help';

  @override
  String get toolbarSignOut => 'Sign out';

  @override
  String get toolbarMoreOptions => 'More options';

  @override
  String get offlineBannerMessage =>
      'You\'re offline — viewing cached data where available; actions that need network may fail.';

  @override
  String get entriesHeadingAll => 'Entries';

  @override
  String get entriesHeadingMine => 'My entries';

  @override
  String get entriesSubtitleAll => 'All recorded giving for your church.';

  @override
  String get entriesSubtitleMine =>
      'Entries you created (pending until the pastor approves).';

  @override
  String get entriesExportPdf => 'PDF';

  @override
  String get entriesExportCsv => 'CSV';

  @override
  String get entriesNewEntry => 'New entry';

  @override
  String get entriesBulkImport => 'Bulk import';

  @override
  String get bulkImportTitle => 'Bulk import entries';

  @override
  String get bulkImportAccessDenied => 'You do not have access to bulk import.';

  @override
  String get bulkImportChurchIndexMissing =>
      'Could not load your church profile yet. Wait a moment and try again, or refresh the page.';

  @override
  String get bulkImportHint =>
      'Choose an .xlsx file (no macros). The sheet must include headers such as Date, Name, Fellowship, Amount, Category (arm), and optionally Pastor confirmation (YES/NO). The active partnership period is applied to all rows.';

  @override
  String get bulkImportUploadTitle => 'Upload spreadsheet';

  @override
  String get bulkImportUploadSubtitle =>
      'Drag and drop your Excel file here, or use Browse.';

  @override
  String get bulkImportDropPrimary => 'Choose a file or drag & drop it here.';

  @override
  String get bulkImportDropFormats =>
      '.xlsx only (no macros). Headers: Date, Name, Fellowship, Amount, Category (arm), optional Pastor confirmation (YES/NO). Active period applies to all rows.';

  @override
  String get bulkImportBrowseFiles => 'Browse files';

  @override
  String get bulkImportParsing => 'Reading…';

  @override
  String get bulkImportPickFile => 'Choose Excel file';

  @override
  String get bulkImportLoadingPartners => 'Loading partners…';

  @override
  String get bulkImportSummary => 'Summary';

  @override
  String bulkImportStatRows(int count) {
    return '$count rows';
  }

  @override
  String bulkImportStatNewPartners(int count) {
    return 'New partners (to create): $count';
  }

  @override
  String bulkImportStatExistingPartners(int count) {
    return 'Existing partners matched: $count';
  }

  @override
  String bulkImportStatTotal(String amount) {
    return 'Total amount: $amount';
  }

  @override
  String bulkImportStatWarnings(int count) {
    return 'Warning flags: $count';
  }

  @override
  String bulkImportStatErrors(int count) {
    return 'Blocking errors: $count';
  }

  @override
  String bulkImportStatPastorYes(int count) {
    return 'Rows marked YES (pastor-confirmed): $count';
  }

  @override
  String get bulkImportStaffPastorNote =>
      'Rows marked YES will stay pending until a pastor approves them.';

  @override
  String get bulkImportPreview => 'Rows';

  @override
  String get bulkImportBlocking =>
      'Fix blocking errors before importing (see row chips).';

  @override
  String get bulkImportNoActivePeriod =>
      'No active partnership period. A pastor must activate a period first.';

  @override
  String bulkImportRowNum(int n) {
    return 'Row $n';
  }

  @override
  String get bulkImportFieldPartner => 'Partner';

  @override
  String get bulkImportFieldArm => 'Arm';

  @override
  String get bulkImportFieldPeriod => 'Period';

  @override
  String get bulkImportFieldNotes => 'Notes';

  @override
  String get bulkImportFieldPastorYes => 'Pastor confirmed';

  @override
  String get bulkImportYes => 'Yes';

  @override
  String get bulkImportNo => 'No';

  @override
  String get bulkImportEditRow => 'Edit row';

  @override
  String bulkImportEditRowTitle(int row) {
    return 'Edit row $row';
  }

  @override
  String get bulkImportFieldDate => 'Date';

  @override
  String get bulkImportFieldName => 'Name';

  @override
  String get bulkImportFieldFellowship => 'Fellowship';

  @override
  String get bulkImportFieldPhone => 'Phone';

  @override
  String get bulkImportFieldEmail => 'Email';

  @override
  String get bulkImportFieldAmount => 'Amount (GHS)';

  @override
  String get bulkImportCancel => 'Cancel';

  @override
  String get bulkImportSave => 'Save';

  @override
  String get bulkImportRemoveRow => 'Remove row';

  @override
  String get bulkImportRemoveRowTitle => 'Remove this row?';

  @override
  String get bulkImportRemoveRowMessage =>
      'This line will be excluded from the import. Choose the Excel file again if you need it back.';

  @override
  String get bulkImportRemoveRowConfirm => 'Remove';

  @override
  String get bulkImportNoRowsInImport =>
      'No rows left in this import. Choose another file to start over.';

  @override
  String get bulkImportResultTitle => 'Import finished';

  @override
  String bulkImportEntriesCreated(int count) {
    return 'Entries created: $count';
  }

  @override
  String bulkImportPartnersCreated(int count) {
    return 'Partners created: $count';
  }

  @override
  String bulkImportApproved(int count) {
    return 'Entries approved (YES rows): $count';
  }

  @override
  String bulkImportSkipped(int count) {
    return 'Rows skipped: $count';
  }

  @override
  String get bulkImportErrorListHeader => 'Messages:';

  @override
  String get bulkImportBack => 'Back to entries';

  @override
  String get bulkImportNeedXlsx =>
      'Please choose an Excel file with the .xlsx extension.';

  @override
  String get bulkImportNoMacros =>
      '.xlsm (macros) is not supported. Save as .xlsx.';

  @override
  String get bulkImportNoBytes => 'Could not read file data.';

  @override
  String get bulkImportNoRows => 'No data rows found under the header.';

  @override
  String get bulkImportParseError => 'Could not read the spreadsheet';

  @override
  String get bulkImportConfirm => 'Import entries';

  @override
  String get bulkImportCompleteImport => 'Complete import';

  @override
  String get bulkImportCommitting => 'Importing…';

  @override
  String get bulkImportTableHeaderRow => 'Row';

  @override
  String get bulkImportTableHeaderPartner => 'Partner';

  @override
  String get bulkImportTableHeaderAmount => 'Amount';

  @override
  String get bulkImportTableHeaderDate => 'Date';

  @override
  String get bulkImportTableHeaderStatus => 'Status';

  @override
  String get bulkImportTableReview => 'Review';

  @override
  String get bulkImportTableRemove => 'Remove';

  @override
  String get bulkImportRowStatusBlocked => 'Blocked';

  @override
  String get bulkImportRowStatusCheck => 'Check';

  @override
  String get bulkImportRowStatusReady => 'Ready';

  @override
  String get bulkImportRowStatusDuplicate => 'Duplicate';

  @override
  String get bulkImportReplaceFile => 'Replace spreadsheet';

  @override
  String get bulkImportConfirmNotDuplicate => 'Confirm new entry';

  @override
  String get bulkImportResolutionExisting => 'Existing partner';

  @override
  String get bulkImportResolutionCreate => 'Will create partner';

  @override
  String get bulkImportResolutionAmbiguous =>
      'Ambiguous — fix phone or member ID';

  @override
  String get bulkImportResolutionUnresolved => 'Unresolved';

  @override
  String get bulkImportIssueMissingName => 'Missing name';

  @override
  String get bulkImportIssueMissingFellowship => 'Missing fellowship';

  @override
  String get bulkImportIssueMissingAmount => 'Missing amount';

  @override
  String get bulkImportIssueInvalidAmount => 'Invalid amount';

  @override
  String get bulkImportIssueMissingDate => 'Missing date';

  @override
  String get bulkImportIssueInvalidDate => 'Invalid date';

  @override
  String get bulkImportIssueMissingArm => 'Missing arm / category';

  @override
  String get bulkImportIssueArmNotFound => 'Arm not found — check spelling';

  @override
  String get bulkImportIssuePeriodNotFound => 'No active period';

  @override
  String get bulkImportIssueAmbiguousPhone =>
      'Several partners share this phone — fix the row';

  @override
  String get bulkImportIssueMemberIdNotFound => 'Member ID not found';

  @override
  String get bulkImportIssueMemberIdConflict =>
      'Member ID does not match phone';

  @override
  String get bulkImportIssueFellowshipMismatch =>
      'Fellowship differs from profile';

  @override
  String get bulkImportIssueNameMismatch => 'Name differs from profile';

  @override
  String get bulkImportIssueDuplicateInFile =>
      'Possible duplicate in this file';

  @override
  String get bulkImportIssueDuplicateInDatabase =>
      'Similar entry may already exist';

  @override
  String get bulkImportIssueStaffPastorYes =>
      'YES — needs pastor approval (staff import)';

  @override
  String get entriesStatusAll => 'All';

  @override
  String get entriesStatusPending => 'Pending';

  @override
  String get entriesStatusApproved => 'Approved';

  @override
  String get entriesStatusDeclined => 'Declined';

  @override
  String get entriesSortNewest => 'Newest first';

  @override
  String get entriesSortOldest => 'Oldest first';

  @override
  String get entriesArmLabel => 'Arm';

  @override
  String get entriesPeriodLabel => 'Period';

  @override
  String get entriesAllArms => 'All arms';

  @override
  String get entriesAllPeriods => 'All periods';

  @override
  String get entriesFilterHint =>
      'Arm/period filters apply to loaded rows; use Load more for older entries.';

  @override
  String entriesShowingLoaded(int count, String more) {
    return 'Showing $count entries loaded$more';
  }

  @override
  String get entriesMoreAvailable => ' — more available below';

  @override
  String get entriesLoadMore => 'Load more';

  @override
  String get entriesLoadingMore => 'Loading…';

  @override
  String get entriesNoEntriesTitle => 'No entries yet';

  @override
  String get entriesNoEntriesMessage => 'Record a new partnership entry.';

  @override
  String get entriesNoMatchesTitle => 'No matches';

  @override
  String get entriesNoMatchesMessage =>
      'Try clearing filters or load more rows.';

  @override
  String get entriesClearFilters => 'Clear filters';

  @override
  String get entriesColPartner => 'PARTNER';

  @override
  String get entriesColAmount => 'AMOUNT';

  @override
  String get entriesColStatus => 'STATUS';

  @override
  String get entriesColSubmitted => 'SUBMITTED';

  @override
  String get entriesView => 'View';

  @override
  String get entriesPdfTitle => 'Partnership entries';

  @override
  String get entrySubmittedTitle => 'Entry submitted';

  @override
  String get entryNotFound => 'Entry not found';

  @override
  String get entrySuccessViewEntry => 'View entry';

  @override
  String get entrySuccessAddAnother => 'Add another';

  @override
  String get entryBackToEntries => 'Back to entries';

  @override
  String get helpIntro =>
      'Partnership entries link a partner, amount, period, and arm. Staff record partnership entries; the pastor approves so totals and goals stay accurate.';

  @override
  String get helpSectionPeriodTitle => 'Period';

  @override
  String get helpSectionPeriodBody =>
      'A partnership period is the time window for giving (for example a quarter or year). Only one period is active at a time. Entries are tied to the period that was active when they were recorded.';

  @override
  String get helpSectionArmTitle => 'Arm';

  @override
  String get helpSectionArmBody =>
      'Arms are categories of giving (for example venue, publications). Your church enables the arms it uses. Each entry picks one arm.';

  @override
  String get helpSectionPartnerTitle => 'Partner';

  @override
  String get helpSectionPartnerBody =>
      'A partner is a member profile. Recording an entry selects the partner who gave, so reports and the leaderboard stay tied to real people.';

  @override
  String get helpSectionApprovalTitle => 'Staff vs pastor approval';

  @override
  String get helpSectionApprovalBody =>
      'Staff and pastors can create entries. New entries are pending until a pastor approves or declines. Only approved entries count toward totals, goals, and leaderboard.';

  @override
  String get helpSectionGoalsTitle => 'Goals';

  @override
  String get helpSectionGoalsBody =>
      'Pastors set target amounts per arm for the active period. Progress updates when entries are approved.';

  @override
  String get helpSectionNotificationsTitle => 'Notifications';

  @override
  String get helpSectionNotificationsBody =>
      'You\'ll get push notifications for important events such as new entries to review and approval outcomes, based on your device settings.';

  @override
  String get goalMilestone50 => 'A partnership goal reached 50% progress.';

  @override
  String get goalMilestone75 => 'A partnership goal reached 75% progress.';

  @override
  String get goalMilestone100 => 'A partnership goal reached 100%!';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsLanguageSystem => 'System default';

  @override
  String get settingsLanguageEnglish => 'English';

  @override
  String get settingsLanguageFrench => 'French';

  @override
  String get pdfTableHeaderPartner => 'Partner';

  @override
  String get pdfTableHeaderAmount => 'Amount';

  @override
  String get pdfTableHeaderStatus => 'Status';

  @override
  String get pdfTableHeaderPeriod => 'Period';

  @override
  String get pdfTableHeaderArm => 'Arm';

  @override
  String get pdfTableHeaderDateGiven => 'Date given';

  @override
  String pdfGeneratedAt(String when) {
    return 'Generated: $when';
  }

  @override
  String pdfExporter(String name) {
    return 'Exporter: $name';
  }

  @override
  String get pdfFooterBrand => 'The Pillr';

  @override
  String get releaseDocTitle => 'Release & App Distribution';
}
