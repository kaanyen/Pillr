import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_fr.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('fr'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Pillr'**
  String get appTitle;

  /// No description provided for @navSectionMain.
  ///
  /// In en, this message translates to:
  /// **'MAIN'**
  String get navSectionMain;

  /// No description provided for @navSectionAdmin.
  ///
  /// In en, this message translates to:
  /// **'ADMIN'**
  String get navSectionAdmin;

  /// No description provided for @navSectionPartnership.
  ///
  /// In en, this message translates to:
  /// **'PARTNERSHIP'**
  String get navSectionPartnership;

  /// No description provided for @navSectionConfiguration.
  ///
  /// In en, this message translates to:
  /// **'CONFIGURATION'**
  String get navSectionConfiguration;

  /// No description provided for @navDashboard.
  ///
  /// In en, this message translates to:
  /// **'Dashboard'**
  String get navDashboard;

  /// No description provided for @navUsers.
  ///
  /// In en, this message translates to:
  /// **'Users'**
  String get navUsers;

  /// No description provided for @navInvitations.
  ///
  /// In en, this message translates to:
  /// **'Invitations'**
  String get navInvitations;

  /// No description provided for @navActivityLogs.
  ///
  /// In en, this message translates to:
  /// **'Activity logs'**
  String get navActivityLogs;

  /// No description provided for @navSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// No description provided for @navEntries.
  ///
  /// In en, this message translates to:
  /// **'Entries'**
  String get navEntries;

  /// No description provided for @navApprovals.
  ///
  /// In en, this message translates to:
  /// **'Approvals'**
  String get navApprovals;

  /// No description provided for @navPartners.
  ///
  /// In en, this message translates to:
  /// **'Partners'**
  String get navPartners;

  /// No description provided for @navLeaderboard.
  ///
  /// In en, this message translates to:
  /// **'Leaderboard'**
  String get navLeaderboard;

  /// No description provided for @navGoals.
  ///
  /// In en, this message translates to:
  /// **'Goals'**
  String get navGoals;

  /// No description provided for @navPartnershipArms.
  ///
  /// In en, this message translates to:
  /// **'Partnership arms'**
  String get navPartnershipArms;

  /// No description provided for @navPeriods.
  ///
  /// In en, this message translates to:
  /// **'Periods'**
  String get navPeriods;

  /// No description provided for @navHelp.
  ///
  /// In en, this message translates to:
  /// **'Help'**
  String get navHelp;

  /// No description provided for @titleDashboard.
  ///
  /// In en, this message translates to:
  /// **'Dashboard'**
  String get titleDashboard;

  /// No description provided for @titleApprovals.
  ///
  /// In en, this message translates to:
  /// **'Approvals'**
  String get titleApprovals;

  /// No description provided for @titleEntries.
  ///
  /// In en, this message translates to:
  /// **'Entries'**
  String get titleEntries;

  /// No description provided for @titleMyEntries.
  ///
  /// In en, this message translates to:
  /// **'My entries'**
  String get titleMyEntries;

  /// No description provided for @titleEntrySubmitted.
  ///
  /// In en, this message translates to:
  /// **'Entry submitted'**
  String get titleEntrySubmitted;

  /// No description provided for @titlePartners.
  ///
  /// In en, this message translates to:
  /// **'Partners'**
  String get titlePartners;

  /// No description provided for @titleLeaderboard.
  ///
  /// In en, this message translates to:
  /// **'Leaderboard'**
  String get titleLeaderboard;

  /// No description provided for @titleGoals.
  ///
  /// In en, this message translates to:
  /// **'Goals'**
  String get titleGoals;

  /// No description provided for @titleArms.
  ///
  /// In en, this message translates to:
  /// **'Partnership arms'**
  String get titleArms;

  /// No description provided for @titlePeriods.
  ///
  /// In en, this message translates to:
  /// **'Periods'**
  String get titlePeriods;

  /// No description provided for @titleUsers.
  ///
  /// In en, this message translates to:
  /// **'Users'**
  String get titleUsers;

  /// No description provided for @titleInvitations.
  ///
  /// In en, this message translates to:
  /// **'Invitations'**
  String get titleInvitations;

  /// No description provided for @titleActivityLogs.
  ///
  /// In en, this message translates to:
  /// **'Activity logs'**
  String get titleActivityLogs;

  /// No description provided for @titleSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get titleSettings;

  /// No description provided for @titleSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get titleSearch;

  /// No description provided for @titleNotifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get titleNotifications;

  /// No description provided for @titleHelp.
  ///
  /// In en, this message translates to:
  /// **'How partnership recording works'**
  String get titleHelp;

  /// No description provided for @titleBulkImport.
  ///
  /// In en, this message translates to:
  /// **'Bulk import'**
  String get titleBulkImport;

  /// No description provided for @searchHint.
  ///
  /// In en, this message translates to:
  /// **'Search church data (partners, entries)…'**
  String get searchHint;

  /// No description provided for @toolbarNotifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get toolbarNotifications;

  /// No description provided for @toolbarHelp.
  ///
  /// In en, this message translates to:
  /// **'Help'**
  String get toolbarHelp;

  /// No description provided for @toolbarSignOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get toolbarSignOut;

  /// No description provided for @toolbarMoreOptions.
  ///
  /// In en, this message translates to:
  /// **'More options'**
  String get toolbarMoreOptions;

  /// No description provided for @offlineBannerMessage.
  ///
  /// In en, this message translates to:
  /// **'You\'re offline — viewing cached data where available; actions that need network may fail.'**
  String get offlineBannerMessage;

  /// No description provided for @entriesHeadingAll.
  ///
  /// In en, this message translates to:
  /// **'Entries'**
  String get entriesHeadingAll;

  /// No description provided for @entriesHeadingMine.
  ///
  /// In en, this message translates to:
  /// **'My entries'**
  String get entriesHeadingMine;

  /// No description provided for @entriesSubtitleAll.
  ///
  /// In en, this message translates to:
  /// **'All recorded giving for your church.'**
  String get entriesSubtitleAll;

  /// No description provided for @entriesSubtitleMine.
  ///
  /// In en, this message translates to:
  /// **'Entries you created (pending until the pastor approves).'**
  String get entriesSubtitleMine;

  /// No description provided for @entriesExportPdf.
  ///
  /// In en, this message translates to:
  /// **'PDF'**
  String get entriesExportPdf;

  /// No description provided for @entriesExportCsv.
  ///
  /// In en, this message translates to:
  /// **'CSV'**
  String get entriesExportCsv;

  /// No description provided for @entriesNewEntry.
  ///
  /// In en, this message translates to:
  /// **'New entry'**
  String get entriesNewEntry;

  /// No description provided for @entriesBulkImport.
  ///
  /// In en, this message translates to:
  /// **'Bulk import'**
  String get entriesBulkImport;

  /// No description provided for @bulkImportTitle.
  ///
  /// In en, this message translates to:
  /// **'Bulk import entries'**
  String get bulkImportTitle;

  /// No description provided for @bulkImportAccessDenied.
  ///
  /// In en, this message translates to:
  /// **'You do not have access to bulk import.'**
  String get bulkImportAccessDenied;

  /// No description provided for @bulkImportChurchIndexMissing.
  ///
  /// In en, this message translates to:
  /// **'Could not load your church profile yet. Wait a moment and try again, or refresh the page.'**
  String get bulkImportChurchIndexMissing;

  /// No description provided for @bulkImportHint.
  ///
  /// In en, this message translates to:
  /// **'Choose an .xlsx file (no macros). The sheet must include headers such as Date, Name, Fellowship, Amount, Category (arm), and optionally Pastor confirmation (YES/NO). The active partnership period is applied to all rows.'**
  String get bulkImportHint;

  /// No description provided for @bulkImportUploadTitle.
  ///
  /// In en, this message translates to:
  /// **'Upload spreadsheet'**
  String get bulkImportUploadTitle;

  /// No description provided for @bulkImportUploadSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Drag and drop your Excel file here, or use Browse.'**
  String get bulkImportUploadSubtitle;

  /// No description provided for @bulkImportDropPrimary.
  ///
  /// In en, this message translates to:
  /// **'Choose a file or drag & drop it here.'**
  String get bulkImportDropPrimary;

  /// No description provided for @bulkImportDropFormats.
  ///
  /// In en, this message translates to:
  /// **'.xlsx only (no macros). Headers: Date, Name, Fellowship, Amount, Category (arm), optional Pastor confirmation (YES/NO). Active period applies to all rows.'**
  String get bulkImportDropFormats;

  /// No description provided for @bulkImportBrowseFiles.
  ///
  /// In en, this message translates to:
  /// **'Browse files'**
  String get bulkImportBrowseFiles;

  /// No description provided for @bulkImportParsing.
  ///
  /// In en, this message translates to:
  /// **'Reading…'**
  String get bulkImportParsing;

  /// No description provided for @bulkImportPickFile.
  ///
  /// In en, this message translates to:
  /// **'Choose Excel file'**
  String get bulkImportPickFile;

  /// No description provided for @bulkImportLoadingPartners.
  ///
  /// In en, this message translates to:
  /// **'Loading partners…'**
  String get bulkImportLoadingPartners;

  /// No description provided for @bulkImportSummary.
  ///
  /// In en, this message translates to:
  /// **'Summary'**
  String get bulkImportSummary;

  /// No description provided for @bulkImportStatRows.
  ///
  /// In en, this message translates to:
  /// **'{count} rows'**
  String bulkImportStatRows(int count);

  /// No description provided for @bulkImportStatNewPartners.
  ///
  /// In en, this message translates to:
  /// **'New partners (to create): {count}'**
  String bulkImportStatNewPartners(int count);

  /// No description provided for @bulkImportStatExistingPartners.
  ///
  /// In en, this message translates to:
  /// **'Existing partners matched: {count}'**
  String bulkImportStatExistingPartners(int count);

  /// No description provided for @bulkImportStatTotal.
  ///
  /// In en, this message translates to:
  /// **'Total amount: {amount}'**
  String bulkImportStatTotal(String amount);

  /// No description provided for @bulkImportStatWarnings.
  ///
  /// In en, this message translates to:
  /// **'Warning flags: {count}'**
  String bulkImportStatWarnings(int count);

  /// No description provided for @bulkImportStatErrors.
  ///
  /// In en, this message translates to:
  /// **'Blocking errors: {count}'**
  String bulkImportStatErrors(int count);

  /// No description provided for @bulkImportStatPastorYes.
  ///
  /// In en, this message translates to:
  /// **'Rows marked YES (pastor-confirmed): {count}'**
  String bulkImportStatPastorYes(int count);

  /// No description provided for @bulkImportStaffPastorNote.
  ///
  /// In en, this message translates to:
  /// **'Rows marked YES will stay pending until a pastor approves them.'**
  String get bulkImportStaffPastorNote;

  /// No description provided for @bulkImportPreview.
  ///
  /// In en, this message translates to:
  /// **'Rows'**
  String get bulkImportPreview;

  /// No description provided for @bulkImportBlocking.
  ///
  /// In en, this message translates to:
  /// **'Fix blocking errors before importing (see row chips).'**
  String get bulkImportBlocking;

  /// No description provided for @bulkImportNoActivePeriod.
  ///
  /// In en, this message translates to:
  /// **'No active partnership period. A pastor must activate a period first.'**
  String get bulkImportNoActivePeriod;

  /// No description provided for @bulkImportRowNum.
  ///
  /// In en, this message translates to:
  /// **'Row {n}'**
  String bulkImportRowNum(int n);

  /// No description provided for @bulkImportFieldPartner.
  ///
  /// In en, this message translates to:
  /// **'Partner'**
  String get bulkImportFieldPartner;

  /// No description provided for @bulkImportFieldArm.
  ///
  /// In en, this message translates to:
  /// **'Arm'**
  String get bulkImportFieldArm;

  /// No description provided for @bulkImportFieldPeriod.
  ///
  /// In en, this message translates to:
  /// **'Period'**
  String get bulkImportFieldPeriod;

  /// No description provided for @bulkImportFieldNotes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get bulkImportFieldNotes;

  /// No description provided for @bulkImportFieldPastorYes.
  ///
  /// In en, this message translates to:
  /// **'Pastor confirmed'**
  String get bulkImportFieldPastorYes;

  /// No description provided for @bulkImportYes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get bulkImportYes;

  /// No description provided for @bulkImportNo.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get bulkImportNo;

  /// No description provided for @bulkImportEditRow.
  ///
  /// In en, this message translates to:
  /// **'Edit row'**
  String get bulkImportEditRow;

  /// No description provided for @bulkImportEditRowTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit row {row}'**
  String bulkImportEditRowTitle(int row);

  /// No description provided for @bulkImportFieldDate.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get bulkImportFieldDate;

  /// No description provided for @bulkImportFieldName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get bulkImportFieldName;

  /// No description provided for @bulkImportFieldFellowship.
  ///
  /// In en, this message translates to:
  /// **'Fellowship'**
  String get bulkImportFieldFellowship;

  /// No description provided for @bulkImportFieldPhone.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get bulkImportFieldPhone;

  /// No description provided for @bulkImportFieldEmail.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get bulkImportFieldEmail;

  /// No description provided for @bulkImportFieldAmount.
  ///
  /// In en, this message translates to:
  /// **'Amount (GHS)'**
  String get bulkImportFieldAmount;

  /// No description provided for @bulkImportCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get bulkImportCancel;

  /// No description provided for @bulkImportSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get bulkImportSave;

  /// No description provided for @bulkImportRemoveRow.
  ///
  /// In en, this message translates to:
  /// **'Remove row'**
  String get bulkImportRemoveRow;

  /// No description provided for @bulkImportRemoveRowTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove this row?'**
  String get bulkImportRemoveRowTitle;

  /// No description provided for @bulkImportRemoveRowMessage.
  ///
  /// In en, this message translates to:
  /// **'This line will be excluded from the import. Choose the Excel file again if you need it back.'**
  String get bulkImportRemoveRowMessage;

  /// No description provided for @bulkImportRemoveRowConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get bulkImportRemoveRowConfirm;

  /// No description provided for @bulkImportNoRowsInImport.
  ///
  /// In en, this message translates to:
  /// **'No rows left in this import. Choose another file to start over.'**
  String get bulkImportNoRowsInImport;

  /// No description provided for @bulkImportResultTitle.
  ///
  /// In en, this message translates to:
  /// **'Import finished'**
  String get bulkImportResultTitle;

  /// No description provided for @bulkImportEntriesCreated.
  ///
  /// In en, this message translates to:
  /// **'Entries created: {count}'**
  String bulkImportEntriesCreated(int count);

  /// No description provided for @bulkImportPartnersCreated.
  ///
  /// In en, this message translates to:
  /// **'Partners created: {count}'**
  String bulkImportPartnersCreated(int count);

  /// No description provided for @bulkImportApproved.
  ///
  /// In en, this message translates to:
  /// **'Entries approved (YES rows): {count}'**
  String bulkImportApproved(int count);

  /// No description provided for @bulkImportSkipped.
  ///
  /// In en, this message translates to:
  /// **'Rows skipped: {count}'**
  String bulkImportSkipped(int count);

  /// No description provided for @bulkImportErrorListHeader.
  ///
  /// In en, this message translates to:
  /// **'Messages:'**
  String get bulkImportErrorListHeader;

  /// No description provided for @bulkImportBack.
  ///
  /// In en, this message translates to:
  /// **'Back to entries'**
  String get bulkImportBack;

  /// No description provided for @bulkImportNeedXlsx.
  ///
  /// In en, this message translates to:
  /// **'Please choose an Excel file with the .xlsx extension.'**
  String get bulkImportNeedXlsx;

  /// No description provided for @bulkImportNoMacros.
  ///
  /// In en, this message translates to:
  /// **'.xlsm (macros) is not supported. Save as .xlsx.'**
  String get bulkImportNoMacros;

  /// No description provided for @bulkImportNoBytes.
  ///
  /// In en, this message translates to:
  /// **'Could not read file data.'**
  String get bulkImportNoBytes;

  /// No description provided for @bulkImportNoRows.
  ///
  /// In en, this message translates to:
  /// **'No data rows found under the header.'**
  String get bulkImportNoRows;

  /// No description provided for @bulkImportParseError.
  ///
  /// In en, this message translates to:
  /// **'Could not read the spreadsheet'**
  String get bulkImportParseError;

  /// No description provided for @bulkImportConfirm.
  ///
  /// In en, this message translates to:
  /// **'Import entries'**
  String get bulkImportConfirm;

  /// No description provided for @bulkImportCompleteImport.
  ///
  /// In en, this message translates to:
  /// **'Complete import'**
  String get bulkImportCompleteImport;

  /// No description provided for @bulkImportCommitting.
  ///
  /// In en, this message translates to:
  /// **'Importing…'**
  String get bulkImportCommitting;

  /// No description provided for @bulkImportTableHeaderRow.
  ///
  /// In en, this message translates to:
  /// **'Row'**
  String get bulkImportTableHeaderRow;

  /// No description provided for @bulkImportTableHeaderPartner.
  ///
  /// In en, this message translates to:
  /// **'Partner'**
  String get bulkImportTableHeaderPartner;

  /// No description provided for @bulkImportTableHeaderAmount.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get bulkImportTableHeaderAmount;

  /// No description provided for @bulkImportTableHeaderDate.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get bulkImportTableHeaderDate;

  /// No description provided for @bulkImportTableHeaderStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get bulkImportTableHeaderStatus;

  /// No description provided for @bulkImportTableReview.
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get bulkImportTableReview;

  /// No description provided for @bulkImportTableRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get bulkImportTableRemove;

  /// No description provided for @bulkImportRowStatusBlocked.
  ///
  /// In en, this message translates to:
  /// **'Blocked'**
  String get bulkImportRowStatusBlocked;

  /// No description provided for @bulkImportRowStatusCheck.
  ///
  /// In en, this message translates to:
  /// **'Check'**
  String get bulkImportRowStatusCheck;

  /// No description provided for @bulkImportRowStatusReady.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get bulkImportRowStatusReady;

  /// No description provided for @bulkImportRowStatusDuplicate.
  ///
  /// In en, this message translates to:
  /// **'Duplicate'**
  String get bulkImportRowStatusDuplicate;

  /// No description provided for @bulkImportReplaceFile.
  ///
  /// In en, this message translates to:
  /// **'Replace spreadsheet'**
  String get bulkImportReplaceFile;

  /// No description provided for @bulkImportConfirmNotDuplicate.
  ///
  /// In en, this message translates to:
  /// **'Confirm new entry'**
  String get bulkImportConfirmNotDuplicate;

  /// No description provided for @bulkImportResolutionExisting.
  ///
  /// In en, this message translates to:
  /// **'Existing partner'**
  String get bulkImportResolutionExisting;

  /// No description provided for @bulkImportResolutionCreate.
  ///
  /// In en, this message translates to:
  /// **'Will create partner'**
  String get bulkImportResolutionCreate;

  /// No description provided for @bulkImportResolutionAmbiguous.
  ///
  /// In en, this message translates to:
  /// **'Ambiguous — fix phone or member ID'**
  String get bulkImportResolutionAmbiguous;

  /// No description provided for @bulkImportResolutionUnresolved.
  ///
  /// In en, this message translates to:
  /// **'Unresolved'**
  String get bulkImportResolutionUnresolved;

  /// No description provided for @bulkImportIssueMissingName.
  ///
  /// In en, this message translates to:
  /// **'Missing name'**
  String get bulkImportIssueMissingName;

  /// No description provided for @bulkImportIssueMissingFellowship.
  ///
  /// In en, this message translates to:
  /// **'Missing fellowship'**
  String get bulkImportIssueMissingFellowship;

  /// No description provided for @bulkImportIssueMissingAmount.
  ///
  /// In en, this message translates to:
  /// **'Missing amount'**
  String get bulkImportIssueMissingAmount;

  /// No description provided for @bulkImportIssueInvalidAmount.
  ///
  /// In en, this message translates to:
  /// **'Invalid amount'**
  String get bulkImportIssueInvalidAmount;

  /// No description provided for @bulkImportIssueMissingDate.
  ///
  /// In en, this message translates to:
  /// **'Missing date'**
  String get bulkImportIssueMissingDate;

  /// No description provided for @bulkImportIssueInvalidDate.
  ///
  /// In en, this message translates to:
  /// **'Invalid date'**
  String get bulkImportIssueInvalidDate;

  /// No description provided for @bulkImportIssueMissingArm.
  ///
  /// In en, this message translates to:
  /// **'Missing arm / category'**
  String get bulkImportIssueMissingArm;

  /// No description provided for @bulkImportIssueArmNotFound.
  ///
  /// In en, this message translates to:
  /// **'Arm not found — check spelling'**
  String get bulkImportIssueArmNotFound;

  /// No description provided for @bulkImportIssuePeriodNotFound.
  ///
  /// In en, this message translates to:
  /// **'No active period'**
  String get bulkImportIssuePeriodNotFound;

  /// No description provided for @bulkImportIssueAmbiguousPhone.
  ///
  /// In en, this message translates to:
  /// **'Several partners share this phone — fix the row'**
  String get bulkImportIssueAmbiguousPhone;

  /// No description provided for @bulkImportIssueMemberIdNotFound.
  ///
  /// In en, this message translates to:
  /// **'Member ID not found'**
  String get bulkImportIssueMemberIdNotFound;

  /// No description provided for @bulkImportIssueMemberIdConflict.
  ///
  /// In en, this message translates to:
  /// **'Member ID does not match phone'**
  String get bulkImportIssueMemberIdConflict;

  /// No description provided for @bulkImportIssueFellowshipMismatch.
  ///
  /// In en, this message translates to:
  /// **'Fellowship differs from profile'**
  String get bulkImportIssueFellowshipMismatch;

  /// No description provided for @bulkImportIssueNameMismatch.
  ///
  /// In en, this message translates to:
  /// **'Name differs from profile'**
  String get bulkImportIssueNameMismatch;

  /// No description provided for @bulkImportIssueDuplicateInFile.
  ///
  /// In en, this message translates to:
  /// **'Possible duplicate in this file'**
  String get bulkImportIssueDuplicateInFile;

  /// No description provided for @bulkImportIssueDuplicateInDatabase.
  ///
  /// In en, this message translates to:
  /// **'Similar entry may already exist'**
  String get bulkImportIssueDuplicateInDatabase;

  /// No description provided for @bulkImportIssueStaffPastorYes.
  ///
  /// In en, this message translates to:
  /// **'YES — needs pastor approval (staff import)'**
  String get bulkImportIssueStaffPastorYes;

  /// No description provided for @entriesStatusAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get entriesStatusAll;

  /// No description provided for @entriesStatusPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get entriesStatusPending;

  /// No description provided for @entriesStatusApproved.
  ///
  /// In en, this message translates to:
  /// **'Approved'**
  String get entriesStatusApproved;

  /// No description provided for @entriesStatusDeclined.
  ///
  /// In en, this message translates to:
  /// **'Declined'**
  String get entriesStatusDeclined;

  /// No description provided for @entriesSortNewest.
  ///
  /// In en, this message translates to:
  /// **'Newest first'**
  String get entriesSortNewest;

  /// No description provided for @entriesSortOldest.
  ///
  /// In en, this message translates to:
  /// **'Oldest first'**
  String get entriesSortOldest;

  /// No description provided for @entriesArmLabel.
  ///
  /// In en, this message translates to:
  /// **'Arm'**
  String get entriesArmLabel;

  /// No description provided for @entriesPeriodLabel.
  ///
  /// In en, this message translates to:
  /// **'Period'**
  String get entriesPeriodLabel;

  /// No description provided for @entriesAllArms.
  ///
  /// In en, this message translates to:
  /// **'All arms'**
  String get entriesAllArms;

  /// No description provided for @entriesAllPeriods.
  ///
  /// In en, this message translates to:
  /// **'All periods'**
  String get entriesAllPeriods;

  /// No description provided for @entriesFilterHint.
  ///
  /// In en, this message translates to:
  /// **'Arm/period filters apply to loaded rows; use Load more for older entries.'**
  String get entriesFilterHint;

  /// No description provided for @entriesShowingLoaded.
  ///
  /// In en, this message translates to:
  /// **'Showing {count} entries loaded{more}'**
  String entriesShowingLoaded(int count, String more);

  /// No description provided for @entriesMoreAvailable.
  ///
  /// In en, this message translates to:
  /// **' — more available below'**
  String get entriesMoreAvailable;

  /// No description provided for @entriesLoadMore.
  ///
  /// In en, this message translates to:
  /// **'Load more'**
  String get entriesLoadMore;

  /// No description provided for @entriesLoadingMore.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get entriesLoadingMore;

  /// No description provided for @entriesNoEntriesTitle.
  ///
  /// In en, this message translates to:
  /// **'No entries yet'**
  String get entriesNoEntriesTitle;

  /// No description provided for @entriesNoEntriesMessage.
  ///
  /// In en, this message translates to:
  /// **'Record a new partnership entry.'**
  String get entriesNoEntriesMessage;

  /// No description provided for @entriesNoMatchesTitle.
  ///
  /// In en, this message translates to:
  /// **'No matches'**
  String get entriesNoMatchesTitle;

  /// No description provided for @entriesNoMatchesMessage.
  ///
  /// In en, this message translates to:
  /// **'Try clearing filters or load more rows.'**
  String get entriesNoMatchesMessage;

  /// No description provided for @entriesClearFilters.
  ///
  /// In en, this message translates to:
  /// **'Clear filters'**
  String get entriesClearFilters;

  /// No description provided for @entriesColPartner.
  ///
  /// In en, this message translates to:
  /// **'PARTNER'**
  String get entriesColPartner;

  /// No description provided for @entriesColAmount.
  ///
  /// In en, this message translates to:
  /// **'AMOUNT'**
  String get entriesColAmount;

  /// No description provided for @entriesColStatus.
  ///
  /// In en, this message translates to:
  /// **'STATUS'**
  String get entriesColStatus;

  /// No description provided for @entriesColSubmitted.
  ///
  /// In en, this message translates to:
  /// **'SUBMITTED'**
  String get entriesColSubmitted;

  /// No description provided for @entriesView.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get entriesView;

  /// No description provided for @entriesPdfTitle.
  ///
  /// In en, this message translates to:
  /// **'Partnership entries'**
  String get entriesPdfTitle;

  /// No description provided for @entrySubmittedTitle.
  ///
  /// In en, this message translates to:
  /// **'Entry submitted'**
  String get entrySubmittedTitle;

  /// No description provided for @entryNotFound.
  ///
  /// In en, this message translates to:
  /// **'Entry not found'**
  String get entryNotFound;

  /// No description provided for @entrySuccessViewEntry.
  ///
  /// In en, this message translates to:
  /// **'View entry'**
  String get entrySuccessViewEntry;

  /// No description provided for @entrySuccessAddAnother.
  ///
  /// In en, this message translates to:
  /// **'Add another'**
  String get entrySuccessAddAnother;

  /// No description provided for @entryBackToEntries.
  ///
  /// In en, this message translates to:
  /// **'Back to entries'**
  String get entryBackToEntries;

  /// No description provided for @helpIntro.
  ///
  /// In en, this message translates to:
  /// **'Partnership entries link a partner, amount, period, and arm. Staff record partnership entries; the pastor approves so totals and goals stay accurate.'**
  String get helpIntro;

  /// No description provided for @helpSectionPeriodTitle.
  ///
  /// In en, this message translates to:
  /// **'Period'**
  String get helpSectionPeriodTitle;

  /// No description provided for @helpSectionPeriodBody.
  ///
  /// In en, this message translates to:
  /// **'A partnership period is the time window for giving (for example a quarter or year). Only one period is active at a time. Entries are tied to the period that was active when they were recorded.'**
  String get helpSectionPeriodBody;

  /// No description provided for @helpSectionArmTitle.
  ///
  /// In en, this message translates to:
  /// **'Arm'**
  String get helpSectionArmTitle;

  /// No description provided for @helpSectionArmBody.
  ///
  /// In en, this message translates to:
  /// **'Arms are categories of giving (for example venue, publications). Your church enables the arms it uses. Each entry picks one arm.'**
  String get helpSectionArmBody;

  /// No description provided for @helpSectionPartnerTitle.
  ///
  /// In en, this message translates to:
  /// **'Partner'**
  String get helpSectionPartnerTitle;

  /// No description provided for @helpSectionPartnerBody.
  ///
  /// In en, this message translates to:
  /// **'A partner is a member profile. Recording an entry selects the partner who gave, so reports and the leaderboard stay tied to real people.'**
  String get helpSectionPartnerBody;

  /// No description provided for @helpSectionApprovalTitle.
  ///
  /// In en, this message translates to:
  /// **'Staff vs pastor approval'**
  String get helpSectionApprovalTitle;

  /// No description provided for @helpSectionApprovalBody.
  ///
  /// In en, this message translates to:
  /// **'Staff and pastors can create entries. New entries are pending until a pastor approves or declines. Only approved entries count toward totals, goals, and leaderboard.'**
  String get helpSectionApprovalBody;

  /// No description provided for @helpSectionGoalsTitle.
  ///
  /// In en, this message translates to:
  /// **'Goals'**
  String get helpSectionGoalsTitle;

  /// No description provided for @helpSectionGoalsBody.
  ///
  /// In en, this message translates to:
  /// **'Pastors set target amounts per arm for the active period. Progress updates when entries are approved.'**
  String get helpSectionGoalsBody;

  /// No description provided for @helpSectionNotificationsTitle.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get helpSectionNotificationsTitle;

  /// No description provided for @helpSectionNotificationsBody.
  ///
  /// In en, this message translates to:
  /// **'You\'ll get push notifications for important events such as new entries to review and approval outcomes, based on your device settings.'**
  String get helpSectionNotificationsBody;

  /// No description provided for @goalMilestone50.
  ///
  /// In en, this message translates to:
  /// **'A partnership goal reached 50% progress.'**
  String get goalMilestone50;

  /// No description provided for @goalMilestone75.
  ///
  /// In en, this message translates to:
  /// **'A partnership goal reached 75% progress.'**
  String get goalMilestone75;

  /// No description provided for @goalMilestone100.
  ///
  /// In en, this message translates to:
  /// **'A partnership goal reached 100%!'**
  String get goalMilestone100;

  /// No description provided for @settingsLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguage;

  /// No description provided for @settingsLanguageSystem.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get settingsLanguageSystem;

  /// No description provided for @settingsLanguageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get settingsLanguageEnglish;

  /// No description provided for @settingsLanguageFrench.
  ///
  /// In en, this message translates to:
  /// **'French'**
  String get settingsLanguageFrench;

  /// No description provided for @pdfTableHeaderPartner.
  ///
  /// In en, this message translates to:
  /// **'Partner'**
  String get pdfTableHeaderPartner;

  /// No description provided for @pdfTableHeaderAmount.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get pdfTableHeaderAmount;

  /// No description provided for @pdfTableHeaderStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get pdfTableHeaderStatus;

  /// No description provided for @pdfTableHeaderPeriod.
  ///
  /// In en, this message translates to:
  /// **'Period'**
  String get pdfTableHeaderPeriod;

  /// No description provided for @pdfTableHeaderArm.
  ///
  /// In en, this message translates to:
  /// **'Arm'**
  String get pdfTableHeaderArm;

  /// No description provided for @pdfTableHeaderDateGiven.
  ///
  /// In en, this message translates to:
  /// **'Date given'**
  String get pdfTableHeaderDateGiven;

  /// No description provided for @pdfGeneratedAt.
  ///
  /// In en, this message translates to:
  /// **'Generated: {when}'**
  String pdfGeneratedAt(String when);

  /// No description provided for @pdfExporter.
  ///
  /// In en, this message translates to:
  /// **'Exporter: {name}'**
  String pdfExporter(String name);

  /// No description provided for @pdfFooterBrand.
  ///
  /// In en, this message translates to:
  /// **'The Pillr'**
  String get pdfFooterBrand;

  /// No description provided for @releaseDocTitle.
  ///
  /// In en, this message translates to:
  /// **'Release & App Distribution'**
  String get releaseDocTitle;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'fr'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'fr':
      return AppLocalizationsFr();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
