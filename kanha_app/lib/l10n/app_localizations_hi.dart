// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Hindi (`hi`).
class AppLocalizationsHi extends AppLocalizations {
  AppLocalizationsHi([String locale = 'hi']) : super(locale);

  @override
  String get appTitle => 'कान्हा QR निगरानी';

  @override
  String get phone => 'फ़ोन नंबर';

  @override
  String get pinOrOtp => 'पिन या वन-टाइम कोड';

  @override
  String get sendOtp => 'वन-टाइम कोड भेजें';

  @override
  String get signIn => 'लॉगिन';

  @override
  String get dueToday => 'आज के काम';

  @override
  String get scanTag => 'टैग स्कैन करें';

  @override
  String get manualCode => 'कोड टाइप करें';

  @override
  String get submit => 'जमा करें';

  @override
  String get next => 'आगे';

  @override
  String get back => 'पीछे';

  @override
  String get yes => 'हाँ';

  @override
  String get no => 'नहीं';

  @override
  String get takePhoto => 'फोटो लें';

  @override
  String get retake => 'फिर से फोटो लें';

  @override
  String waitingUpload(int count) {
    return '$count अपलोड के लिए प्रतीक्षा में';
  }

  @override
  String get syncNow => 'अभी सिंक करें';

  @override
  String get allSynced => 'सब सिंक हो गया';

  @override
  String get newAsset => 'नया बिंदु';

  @override
  String get issues => 'समस्याएँ';

  @override
  String get noticeTitle => 'आपका डेटा कैसे इस्तेमाल होता है';

  @override
  String get noticeBody =>
      'आपकी लोकेशन केवल स्कैन या फोटो लेते समय दर्ज होती है। बैकग्राउंड में ट्रैकिंग नहीं होती। नियंत्रण बिंदुओं की फोटो लें, लोगों की नहीं।';

  @override
  String get ok => 'ठीक है';

  @override
  String get logout => 'लॉग आउट';

  @override
  String get tagInactive =>
      'यह टैग अब चालू नहीं है। कृपया सुपरवाइज़र को बताएँ।';

  @override
  String get saved => 'सेव हो गया। ऑनलाइन होने पर अपलोड होगा।';

  @override
  String get photoRequired => 'फोटो ज़रूरी है';

  @override
  String get assetName => 'नाम';

  @override
  String get chooseType => 'प्रकार';

  @override
  String get chooseZone => 'ज़ोन';

  @override
  String get save => 'सेव करें';

  @override
  String get fixIssue =>
      'ठीक करने के लिए: वही टैग स्कैन करें, फिर बाद की फोटो लें';

  @override
  String get wrongTag => 'यह उस नियंत्रण बिंदु का टैग नहीं है';

  @override
  String get nothingDue => 'आज कुछ बाकी नहीं';
}
