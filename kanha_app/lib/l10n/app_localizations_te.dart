// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Telugu (`te`).
class AppLocalizationsTe extends AppLocalizations {
  AppLocalizationsTe([String locale = 'te']) : super(locale);

  @override
  String get appTitle => 'కన్హా QR పర్యవేక్షణ';

  @override
  String get phone => 'ఫోన్ నంబర్';

  @override
  String get pinOrOtp => 'పిన్ లేదా వన్-టైమ్ కోడ్';

  @override
  String get sendOtp => 'వన్-టైమ్ కోడ్ పంపండి';

  @override
  String get signIn => 'లాగిన్';

  @override
  String get dueToday => 'ఈ రోజు చేయాల్సినవి';

  @override
  String get scanTag => 'ట్యాగ్ స్కాన్ చేయండి';

  @override
  String get manualCode => 'కోడ్ టైప్ చేయండి';

  @override
  String get submit => 'సమర్పించండి';

  @override
  String get next => 'తదుపరి';

  @override
  String get back => 'వెనుకకు';

  @override
  String get yes => 'అవును';

  @override
  String get no => 'కాదు';

  @override
  String get takePhoto => 'ఫోటో తీయండి';

  @override
  String get retake => 'మళ్ళీ తీయండి';

  @override
  String waitingUpload(int count) {
    return '$count అప్‌లోడ్ కోసం వేచి ఉన్నాయి';
  }

  @override
  String get syncNow => 'ఇప్పుడు సింక్ చేయండి';

  @override
  String get allSynced => 'అన్నీ సింక్ అయ్యాయి';

  @override
  String get newAsset => 'కొత్త పాయింట్';

  @override
  String get issues => 'సమస్యలు';

  @override
  String get noticeTitle => 'మీ డేటా ఎలా ఉపయోగిస్తారు';

  @override
  String get noticeBody =>
      'మీరు స్కాన్ చేసినప్పుడు లేదా ఫోటో తీసినప్పుడు మాత్రమే మీ లొకేషన్ నమోదు అవుతుంది. బ్యాక్‌గ్రౌండ్‌లో ట్రాక్ చేయము. నియంత్రణ పాయింట్ల ఫోటోలు తీయండి, మనుషులవి కాదు.';

  @override
  String get ok => 'సరే';

  @override
  String get logout => 'లాగ్ అవుట్';

  @override
  String get tagInactive =>
      'ఈ ట్యాగ్ ఇకపై పనిచేయదు. దయచేసి సూపర్‌వైజర్‌కు చెప్పండి.';

  @override
  String get saved => 'సేవ్ అయింది. ఆన్‌లైన్‌లో ఉన్నప్పుడు అప్‌లోడ్ అవుతుంది.';

  @override
  String get photoRequired => 'ఫోటో అవసరం';

  @override
  String get assetName => 'పేరు';

  @override
  String get chooseType => 'రకం';

  @override
  String get chooseZone => 'జోన్';

  @override
  String get save => 'సేవ్';

  @override
  String get fixIssue =>
      'సరిచేయడానికి: అదే ట్యాగ్ స్కాన్ చేసి, తర్వాత ఫోటో తీయండి';

  @override
  String get wrongTag => 'ఇది ఆ నియంత్రణ పాయింట్ ట్యాగ్ కాదు';

  @override
  String get nothingDue => 'ఈ రోజు ఏమీ లేదు';

  @override
  String get reportIssue => 'సమస్యను నివేదించండి';

  @override
  String get noIssues => 'ఎటువంటి సమస్యలు లేవు';

  @override
  String get filterAll => 'అన్నీ';

  @override
  String get filterOpen => 'తెరిచి ఉంది';

  @override
  String get filterFixed => 'పరిష్కరించబడింది';

  @override
  String get severityHigh => 'అధిక ప్రాధాన్యత';

  @override
  String get severityMedium => 'మధ్యస్థ ప్రాధాన్యత';

  @override
  String get severityLow => 'తక్కువ ప్రాధాన్యత';

  @override
  String get issueCategory => 'వర్గం';

  @override
  String get issueDescription => 'వివరణ';

  @override
  String get issueFixedSuccess => 'సమస్య పరిష్కరించబడింది.';

  @override
  String get issueReportedSuccess => 'సమస్య నివేదించబడింది.';

  @override
  String get selectAsset => 'నియంత్రణ స్థానాన్ని ఎంచుకోండి';

  @override
  String get fixInstruction =>
      'పరిష్కరించడానికి: అదే QR ట్యాగ్‌ను స్కాన్ చేసి ఫోటో తీయండి.';
}
