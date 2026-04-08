// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get appTitle => 'Pillr';

  @override
  String get navSectionMain => 'PRINCIPAL';

  @override
  String get navSectionAdmin => 'ADMIN';

  @override
  String get navSectionPartnership => 'PARTENARIAT';

  @override
  String get navSectionConfiguration => 'CONFIGURATION';

  @override
  String get navDashboard => 'Tableau de bord';

  @override
  String get navUsers => 'Utilisateurs';

  @override
  String get navInvitations => 'Invitations';

  @override
  String get navActivityLogs => 'Journal d\'activité';

  @override
  String get navSettings => 'Paramètres';

  @override
  String get navEntries => 'Saisies';

  @override
  String get navApprovals => 'Approbations';

  @override
  String get navPartners => 'Partenaires';

  @override
  String get navLeaderboard => 'Classement';

  @override
  String get navGoals => 'Objectifs';

  @override
  String get navPartnershipArms => 'Bras de partenariat';

  @override
  String get navPeriods => 'Périodes';

  @override
  String get navHelp => 'Aide';

  @override
  String get titleDashboard => 'Tableau de bord';

  @override
  String get titleApprovals => 'Approbations';

  @override
  String get titleEntries => 'Saisies';

  @override
  String get titleMyEntries => 'Mes saisies';

  @override
  String get titleEntrySubmitted => 'Saisie envoyée';

  @override
  String get titlePartners => 'Partenaires';

  @override
  String get titleLeaderboard => 'Classement';

  @override
  String get titleGoals => 'Objectifs';

  @override
  String get titleArms => 'Bras de partenariat';

  @override
  String get titlePeriods => 'Périodes';

  @override
  String get titleUsers => 'Utilisateurs';

  @override
  String get titleInvitations => 'Invitations';

  @override
  String get titleActivityLogs => 'Journal d\'activité';

  @override
  String get titleSettings => 'Paramètres';

  @override
  String get titleSearch => 'Recherche';

  @override
  String get titleNotifications => 'Notifications';

  @override
  String get titleHelp => 'Fonctionnement du suivi du partenariat';

  @override
  String get searchHint => 'Rechercher dans l\'église (partenaires, saisies)…';

  @override
  String get toolbarNotifications => 'Notifications';

  @override
  String get toolbarHelp => 'Aide';

  @override
  String get toolbarSignOut => 'Se déconnecter';

  @override
  String get toolbarMoreOptions => 'Plus d\'options';

  @override
  String get offlineBannerMessage =>
      'Vous êtes hors ligne — affichage des données en cache si disponibles ; les actions nécessitant le réseau peuvent échouer.';

  @override
  String get entriesHeadingAll => 'Saisies';

  @override
  String get entriesHeadingMine => 'Mes saisies';

  @override
  String get entriesSubtitleAll =>
      'Tous les dons enregistrés pour votre église.';

  @override
  String get entriesSubtitleMine =>
      'Saisies que vous avez créées (en attente jusqu\'à l\'approbation du pasteur).';

  @override
  String get entriesExportPdf => 'PDF';

  @override
  String get entriesExportCsv => 'CSV';

  @override
  String get entriesNewEntry => 'Nouvelle saisie';

  @override
  String get entriesBulkImport => 'Import groupé';

  @override
  String get bulkImportTitle => 'Import groupé de saisies';

  @override
  String get bulkImportAccessDenied =>
      'Vous n\'avez pas accès à l\'import groupé.';

  @override
  String get bulkImportChurchIndexMissing =>
      'Impossible de charger votre profil d\'église pour le moment. Patientez un instant et réessayez, ou actualisez la page.';

  @override
  String get bulkImportHint =>
      'Choisissez un fichier .xlsx (sans macros). La feuille doit inclure des en-têtes tels que Date, Nom, Communauté, Montant, Catégorie (bras) et éventuellement Confirmation pasteur (OUI/NON). La période de partenariat active s\'applique à toutes les lignes.';

  @override
  String get bulkImportParsing => 'Lecture…';

  @override
  String get bulkImportPickFile => 'Choisir un fichier Excel';

  @override
  String get bulkImportLoadingPartners => 'Chargement des partenaires…';

  @override
  String get bulkImportSummary => 'Résumé';

  @override
  String bulkImportStatRows(int count) {
    return '$count lignes';
  }

  @override
  String bulkImportStatNewPartners(int count) {
    return 'Nouveaux partenaires (à créer) : $count';
  }

  @override
  String bulkImportStatExistingPartners(int count) {
    return 'Partenaires existants reconnus : $count';
  }

  @override
  String bulkImportStatTotal(String amount) {
    return 'Montant total : $amount';
  }

  @override
  String bulkImportStatWarnings(int count) {
    return 'Avertissements : $count';
  }

  @override
  String bulkImportStatErrors(int count) {
    return 'Erreurs bloquantes : $count';
  }

  @override
  String bulkImportStatPastorYes(int count) {
    return 'Lignes marquées OUI (confirmées pasteur) : $count';
  }

  @override
  String get bulkImportStaffPastorNote =>
      'Les lignes marquées OUI restent en attente jusqu\'à approbation par un pasteur.';

  @override
  String get bulkImportPreview => 'Lignes';

  @override
  String get bulkImportBlocking =>
      'Corrigez les erreurs bloquantes avant l\'import (voir les pastilles par ligne).';

  @override
  String get bulkImportNoActivePeriod =>
      'Aucune période de partenariat active. Un pasteur doit activer une période d\'abord.';

  @override
  String bulkImportRowNum(int n) {
    return 'Ligne $n';
  }

  @override
  String get bulkImportFieldPartner => 'Partenaire';

  @override
  String get bulkImportFieldArm => 'Bras';

  @override
  String get bulkImportFieldPeriod => 'Période';

  @override
  String get bulkImportFieldNotes => 'Notes';

  @override
  String get bulkImportFieldPastorYes => 'Confirmé pasteur';

  @override
  String get bulkImportYes => 'Oui';

  @override
  String get bulkImportNo => 'Non';

  @override
  String get bulkImportEditRow => 'Modifier la ligne';

  @override
  String bulkImportEditRowTitle(int row) {
    return 'Modifier la ligne $row';
  }

  @override
  String get bulkImportFieldDate => 'Date';

  @override
  String get bulkImportFieldName => 'Nom';

  @override
  String get bulkImportFieldFellowship => 'Communauté';

  @override
  String get bulkImportFieldPhone => 'Téléphone';

  @override
  String get bulkImportFieldEmail => 'E-mail';

  @override
  String get bulkImportFieldAmount => 'Montant (GHS)';

  @override
  String get bulkImportCancel => 'Annuler';

  @override
  String get bulkImportSave => 'Enregistrer';

  @override
  String get bulkImportRemoveRow => 'Retirer la ligne';

  @override
  String get bulkImportRemoveRowTitle => 'Retirer cette ligne ?';

  @override
  String get bulkImportRemoveRowMessage =>
      'Cette ligne sera exclue de l\'import. Choisissez à nouveau le fichier Excel si vous devez la réintégrer.';

  @override
  String get bulkImportRemoveRowConfirm => 'Retirer';

  @override
  String get bulkImportNoRowsInImport =>
      'Aucune ligne dans cet import. Choisissez un autre fichier pour recommencer.';

  @override
  String get bulkImportResultTitle => 'Import terminé';

  @override
  String bulkImportEntriesCreated(int count) {
    return 'Saisies créées : $count';
  }

  @override
  String bulkImportPartnersCreated(int count) {
    return 'Partenaires créés : $count';
  }

  @override
  String bulkImportApproved(int count) {
    return 'Saisies approuvées (lignes OUI) : $count';
  }

  @override
  String bulkImportSkipped(int count) {
    return 'Lignes ignorées : $count';
  }

  @override
  String get bulkImportErrorListHeader => 'Messages :';

  @override
  String get bulkImportBack => 'Retour aux saisies';

  @override
  String get bulkImportNeedXlsx =>
      'Veuillez choisir un fichier Excel avec l\'extension .xlsx.';

  @override
  String get bulkImportNoMacros =>
      'Les fichiers .xlsm (macros) ne sont pas pris en charge. Enregistrez en .xlsx.';

  @override
  String get bulkImportNoBytes => 'Impossible de lire les données du fichier.';

  @override
  String get bulkImportNoRows => 'Aucune ligne de données sous l\'en-tête.';

  @override
  String get bulkImportParseError => 'Impossible de lire le classeur';

  @override
  String get bulkImportConfirm => 'Importer les saisies';

  @override
  String get bulkImportCommitting => 'Import…';

  @override
  String get bulkImportResolutionExisting => 'Partenaire existant';

  @override
  String get bulkImportResolutionCreate => 'Création du partenaire';

  @override
  String get bulkImportResolutionAmbiguous =>
      'Ambigu — corrigez le téléphone ou l\'ID membre';

  @override
  String get bulkImportResolutionUnresolved => 'Non résolu';

  @override
  String get bulkImportIssueMissingName => 'Nom manquant';

  @override
  String get bulkImportIssueMissingFellowship => 'Communauté manquante';

  @override
  String get bulkImportIssueMissingAmount => 'Montant manquant';

  @override
  String get bulkImportIssueInvalidAmount => 'Montant invalide';

  @override
  String get bulkImportIssueMissingDate => 'Date manquante';

  @override
  String get bulkImportIssueInvalidDate => 'Date invalide';

  @override
  String get bulkImportIssueMissingArm => 'Bras / catégorie manquant';

  @override
  String get bulkImportIssueArmNotFound =>
      'Bras introuvable — vérifiez l\'orthographe';

  @override
  String get bulkImportIssuePeriodNotFound => 'Aucune période active';

  @override
  String get bulkImportIssueAmbiguousPhone =>
      'Plusieurs partenaires partagent ce téléphone — corrigez la ligne';

  @override
  String get bulkImportIssueMemberIdNotFound => 'ID membre introuvable';

  @override
  String get bulkImportIssueMemberIdConflict =>
      'L\'ID membre ne correspond pas au téléphone';

  @override
  String get bulkImportIssueFellowshipMismatch =>
      'Communauté différente du profil';

  @override
  String get bulkImportIssueNameMismatch => 'Nom différent du profil';

  @override
  String get bulkImportIssueDuplicateInFile =>
      'Doublon possible dans ce fichier';

  @override
  String get bulkImportIssueDuplicateInDatabase =>
      'Une saisie similaire existe peut-être déjà';

  @override
  String get bulkImportIssueStaffPastorYes =>
      'OUI — approbation pasteur requise (import personnel)';

  @override
  String get entriesStatusAll => 'Tous';

  @override
  String get entriesStatusPending => 'En attente';

  @override
  String get entriesStatusApproved => 'Approuvé';

  @override
  String get entriesStatusDeclined => 'Refusé';

  @override
  String get entriesSortNewest => 'Plus récent d\'abord';

  @override
  String get entriesSortOldest => 'Plus ancien d\'abord';

  @override
  String get entriesArmLabel => 'Bras';

  @override
  String get entriesPeriodLabel => 'Période';

  @override
  String get entriesAllArms => 'Tous les bras';

  @override
  String get entriesAllPeriods => 'Toutes les périodes';

  @override
  String get entriesFilterHint =>
      'Les filtres bras/période s\'appliquent aux lignes chargées ; utilisez « Charger plus » pour les anciennes saisies.';

  @override
  String entriesShowingLoaded(int count, String more) {
    return 'Affichage de $count saisies chargées$more';
  }

  @override
  String get entriesMoreAvailable => ' — d\'autres disponibles ci-dessous';

  @override
  String get entriesLoadMore => 'Charger plus';

  @override
  String get entriesLoadingMore => 'Chargement…';

  @override
  String get entriesNoEntriesTitle => 'Aucune saisie pour l\'instant';

  @override
  String get entriesNoEntriesMessage =>
      'Enregistrez une nouvelle saisie de partenariat.';

  @override
  String get entriesNoMatchesTitle => 'Aucun résultat';

  @override
  String get entriesNoMatchesMessage =>
      'Essayez d\'effacer les filtres ou de charger plus de lignes.';

  @override
  String get entriesClearFilters => 'Effacer les filtres';

  @override
  String get entriesColPartner => 'PARTENAIRE';

  @override
  String get entriesColAmount => 'MONTANT';

  @override
  String get entriesColStatus => 'STATUT';

  @override
  String get entriesColSubmitted => 'ENVOYÉ';

  @override
  String get entriesView => 'Voir';

  @override
  String get entriesPdfTitle => 'Saisies de partenariat';

  @override
  String get entrySubmittedTitle => 'Saisie envoyée';

  @override
  String get entryNotFound => 'Saisie introuvable';

  @override
  String get entrySuccessViewEntry => 'Voir la saisie';

  @override
  String get entrySuccessAddAnother => 'Ajouter une autre';

  @override
  String get entryBackToEntries => 'Retour aux saisies';

  @override
  String get helpIntro =>
      'Les saisies de partenariat lient un partenaire, un montant, une période et un bras. Le personnel enregistre les dons ; le pasteur approuve pour que les totaux et objectifs restent exacts.';

  @override
  String get helpSectionPeriodTitle => 'Période';

  @override
  String get helpSectionPeriodBody =>
      'Une période de partenariat est la fenêtre de temps pour les dons (par exemple un trimestre ou une année). Une seule période est active à la fois. Les saisies sont liées à la période active au moment de l\'enregistrement.';

  @override
  String get helpSectionArmTitle => 'Bras';

  @override
  String get helpSectionArmBody =>
      'Les bras sont des catégories de dons (par exemple lieu, publications). Votre église active les bras utilisés. Chaque saisie choisit un bras.';

  @override
  String get helpSectionPartnerTitle => 'Partenaire';

  @override
  String get helpSectionPartnerBody =>
      'Un partenaire est un profil de membre. Enregistrer une saisie sélectionne le donateur, afin que les rapports et le classement restent liés aux personnes.';

  @override
  String get helpSectionApprovalTitle => 'Personnel et approbation pasteur';

  @override
  String get helpSectionApprovalBody =>
      'Le personnel et les pasteurs peuvent créer des saisies. Elles sont en attente jusqu\'à approbation ou refus par un pasteur. Seules les saisies approuvées comptent pour les totaux, objectifs et classement.';

  @override
  String get helpSectionGoalsTitle => 'Objectifs';

  @override
  String get helpSectionGoalsBody =>
      'Les pasteurs fixent des cibles par bras pour la période active. La progression se met à jour lorsque les saisies sont approuvées.';

  @override
  String get helpSectionNotificationsTitle => 'Notifications';

  @override
  String get helpSectionNotificationsBody =>
      'Vous recevez des notifications push pour les événements importants (nouvelles saisies à examiner, résultats d\'approbation), selon les réglages de l\'appareil.';

  @override
  String get goalMilestone50 =>
      'Un objectif de partenariat a atteint 50 % de progression.';

  @override
  String get goalMilestone75 =>
      'Un objectif de partenariat a atteint 75 % de progression.';

  @override
  String get goalMilestone100 => 'Un objectif de partenariat a atteint 100 % !';

  @override
  String get settingsLanguage => 'Langue';

  @override
  String get settingsLanguageSystem => 'Par défaut du système';

  @override
  String get settingsLanguageEnglish => 'Anglais';

  @override
  String get settingsLanguageFrench => 'Français';

  @override
  String get pdfTableHeaderPartner => 'Partenaire';

  @override
  String get pdfTableHeaderAmount => 'Montant';

  @override
  String get pdfTableHeaderStatus => 'Statut';

  @override
  String get pdfTableHeaderPeriod => 'Période';

  @override
  String get pdfTableHeaderArm => 'Bras';

  @override
  String get pdfTableHeaderDateGiven => 'Date du don';

  @override
  String pdfGeneratedAt(String when) {
    return 'Généré : $when';
  }

  @override
  String pdfExporter(String name) {
    return 'Exportateur : $name';
  }

  @override
  String get pdfFooterBrand => 'The Pillr';

  @override
  String get releaseDocTitle => 'Publication et distribution d\'application';
}
