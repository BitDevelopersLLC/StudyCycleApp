# Security Policy

## Reporting a problem

If you find a security or privacy problem in Study Cycle, please email
**support@studycycle.app** with "Security" in the subject. Please don't open a public issue for it.

We'll reply within 7 days and keep you informed until it is fixed. We're happy to credit you in
the changelog if you'd like.

## Supported versions

Only the latest version in the App Store and Google Play receives fixes.

## Design notes for reviewers

- The app has no network code and, on Android, no `INTERNET` permission.
- All data lives in the platform's app preferences (SharedPreferences / NSUserDefaults). Damaged
  or unexpected saved data is discarded, never trusted (see `TimerState.fromJson` and
  `StudyHistory.fromJson`).
- The notification receivers are not exported, so other apps can't trigger them.
- Android backup is off (`android:allowBackup="false"`).
- Third-party packages are kept to a minimum: `shared_preferences`, `flutter_local_notifications`
  and `timezone`. Each is a widely used package from pub.dev.
