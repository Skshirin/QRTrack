// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Kanha QR Monitoring';

  @override
  String get phone => 'Phone number';

  @override
  String get pinOrOtp => 'PIN or one-time code';

  @override
  String get sendOtp => 'Send one-time code';

  @override
  String get signIn => 'Sign in';

  @override
  String get dueToday => 'Due today';

  @override
  String get scanTag => 'Scan tag';

  @override
  String get manualCode => 'Type the code';

  @override
  String get submit => 'Submit';

  @override
  String get next => 'Next';

  @override
  String get back => 'Back';

  @override
  String get yes => 'Yes';

  @override
  String get no => 'No';

  @override
  String get takePhoto => 'Take photo';

  @override
  String get retake => 'Retake photo';

  @override
  String waitingUpload(int count) {
    return '$count waiting to upload';
  }

  @override
  String get syncNow => 'Sync now';

  @override
  String get allSynced => 'All synced';

  @override
  String get newAsset => 'New point';

  @override
  String get issues => 'Issues';

  @override
  String get noticeTitle => 'How your data is used';

  @override
  String get noticeBody =>
      'Your location is recorded only at the moment you scan or take a photo. We never track you in the background. Photograph control points, not people.';

  @override
  String get ok => 'OK';

  @override
  String get logout => 'Log out';

  @override
  String get tagInactive =>
      'This tag is no longer active. Please report it to your supervisor.';

  @override
  String get saved => 'Saved. It will upload when you are online.';

  @override
  String get photoRequired => 'A photo is required';

  @override
  String get assetName => 'Name';

  @override
  String get chooseType => 'Type';

  @override
  String get chooseZone => 'Zone';

  @override
  String get save => 'Save';

  @override
  String get fixIssue => 'Fix: scan the same tag, then take the after-photo';

  @override
  String get wrongTag => 'This is not the tag of that control point';

  @override
  String get nothingDue => 'Nothing due today';

  @override
  String get reportIssue => 'Report Issue';

  @override
  String get noIssues => 'No issues reported';

  @override
  String get filterAll => 'All';

  @override
  String get filterOpen => 'Open';

  @override
  String get filterFixed => 'Fixed';

  @override
  String get severityHigh => 'High';

  @override
  String get severityMedium => 'Medium';

  @override
  String get severityLow => 'Low';

  @override
  String get issueCategory => 'Category';

  @override
  String get issueDescription => 'Description / Notes';

  @override
  String get issueFixedSuccess =>
      'Issue marked as fixed and queued for verification.';

  @override
  String get issueReportedSuccess => 'Issue reported and saved offline.';

  @override
  String get selectAsset => 'Select Control Point';

  @override
  String get fixInstruction =>
      'To fix: scan the same QR tag, then capture an after-photo.';
}
