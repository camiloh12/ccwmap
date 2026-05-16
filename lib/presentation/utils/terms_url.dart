import 'package:url_launcher/url_launcher.dart';

/// Public Terms-of-Use page hosted on GitHub Pages.
const termsUrl = 'https://camiloh12.github.io/ccwmap/terms';

/// Opens the Terms-of-Use page in the system browser. No-ops if the
/// platform refuses to launch the URL.
Future<void> openTermsUrl() async {
  final uri = Uri.parse(termsUrl);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
