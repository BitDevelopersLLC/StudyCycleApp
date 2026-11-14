# Contributing to Study Cycle

Thanks for helping. This file explains the promises the app makes, where code goes, how to add a
feature, and how a release is made. Read [README.md](README.md) first for what the app does and how
to build it.

## The promises (these don't change)

Every change must keep these. A pull request that breaks one won't be merged.

1. **Free.** No price, no subscription, no paid upgrades.
2. **Nothing collected.** No accounts, ads, analytics, crash reporting or network calls. The
   Android release build must have **no `INTERNET` permission**. After adding or upgrading any
   plugin, check it:
   ```bash
   cd mobile && flutter build apk --release
   aapt dump permissions build/app/outputs/flutter-apk/app-release.apk
   ```
   The expected list is in [PRIVACY.md](PRIVACY.md). If a permission changes, PRIVACY.md and the
   website's privacy page (`website/privacy.html`) must change in the same pull request.
3. **Honest about the research.** Never call a cycle length "proven" or "optimal". The About screen
   and the website say what the studies show and what they don't.
4. **No "Pomodoro".** It's a trademark. Don't use the word in the app, the website or store text.

## Where code goes

```
mobile/lib/
  domain/       Pure Dart rules, no Flutter imports, fully unit-tested
  data/         Saving and loading (app_store.dart, shared_preferences)
  controller/   StudyController: connects the rules to storage, alerts and the screen
  platform/     Notifications and the keep-screen-on channel
  ui/           Screens and widgets
mobile/test/    Tests, in the same folder layout as lib/
website/        studycycle.app (static HTML/CSS, no scripts)
website/app/    The browser version of the timer (plain JavaScript)
tools/          Screenshot and store-image scripts, web engine tests
```

Rules for the timer:

- The timer stores **when the current phase ends**, never a countdown. The current state is always
  worked out from the clock, so it survives the app being killed or the phone restarting.
- **`TimerEngine` (`domain/timer_engine.dart`) is the only place state changes.** UI and controller
  code asks the engine for the next state; it never edits `TimerState` itself.
- Alerts are planned in `domain/phase_alerts.dart` and scheduled on the device by
  `platform/`. There's no server.

## Adding a feature, step by step

1. **Open an issue first** for anything bigger than a small fix, so we can agree on the behaviour.
2. **Rules first.** Put the logic in `mobile/lib/domain/` as plain Dart and write unit tests for it
   in `mobile/test/domain/`. Cover the edge cases: pause/resume, app killed, phone restarted,
   midnight and time-zone changes for anything date-based.
3. **Storage.** If the feature saves something, add it to `data/app_store.dart` with a default, so
   older installs that don't have the value yet still load. Never remove or rename a saved key
   without a migration.
4. **Controller and UI.** Wire it up in `controller/study_controller.dart` and `ui/`. Every new
   control needs a screen-reader label, and the layout must still work at the largest system font
   size, in dark mode and on tablets.
5. **Web version.** `website/app/engine.js` is a port of `mobile/lib/domain/`. If you changed a
   rule there, change `engine.js` and `tools/web-test/engine.test.mjs` the same way.
6. **Docs.** Add a line under `## [Unreleased]` in [CHANGELOG.md](CHANGELOG.md). Update README.md if
   the "What it does" list changes, and PRIVACY.md if anything about data or permissions changes.

## Checks before every pull request

```bash
cd mobile
flutter analyze                          # must say "No issues found!"
flutter test                             # all pass
cd ..
node --test tools/web-test/engine.test.mjs   # all pass (Node 20+)
```

Code style: doc comments on every public member, the lints in `mobile/analysis_options.yaml`, and
lines up to 100 characters (`dart format .` in `mobile/` uses that width).

## Making a release (maintainers)

1. Move the `[Unreleased]` notes in CHANGELOG.md under a new version heading with the date.
2. Bump `version:` in `mobile/pubspec.yaml`. The number after `+` is the Android versionCode and
   the iOS build number, and it must be higher than any build already uploaded to either store.
   1.0.0 used versionCode 1 on Android and build 2 on iOS, so the next release starts at `+3`
   (for example `1.1.0+3`), which works for both.
3. Run all the checks above, and the Android permission check.
4. Build: `flutter build appbundle --release` (Android, needs the private upload key) and
   `flutter build ipa` on a Mac (iOS). Upload, then submit for review in Play Console and App Store
   Connect.
5. When both stores have approved it: commit, tag `vX.Y.Z`, push the tag, and create a GitHub
   release with the CHANGELOG notes.

## Reporting problems

Bugs and ideas: open a GitHub issue, or email support@studycycle.app. Security problems: see
[SECURITY.md](SECURITY.md) and please don't open a public issue.

By contributing, you agree that your contribution is licensed under the GPL-3.0, like the rest of
the project.
