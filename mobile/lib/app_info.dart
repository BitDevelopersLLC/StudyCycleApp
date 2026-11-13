/// Facts about the app shown on the About screen.
library;

/// App name, version and links. The version is checked against pubspec.yaml by a test.
abstract final class AppInfo {
  /// The app's name.
  static const String name = 'Study Cycle';

  /// The version shown to users. Must match `version:` in pubspec.yaml (without the build).
  static const String version = '1.0.0';

  /// The app's website.
  static const String website = 'https://studycycle.app';

  /// The privacy policy.
  static const String privacyUrl = 'https://studycycle.app/privacy';

  /// The public source code.
  static const String sourceUrl = 'https://github.com/BitDevelopersLLC/StudyCycleApp';

  /// Where to send questions and bug reports.
  static const String supportEmail = 'support@studycycle.app';
}
