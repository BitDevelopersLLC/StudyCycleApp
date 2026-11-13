# Study Cycle

**Study Cycle** is a free study timer for iPhone and Android. Focus on one task for a set time,
then take a real break. It's built around 90-minute cycles, and you can switch to 50 or 25
minutes or choose your own lengths.

- **Free.** No price, no subscription, no "premium."
- **No ads, no account, no tracking.** The app collects nothing. See [PRIVACY.md](PRIVACY.md).
- **Works offline.** The Android app doesn't even have internet access.
- **Open source** (GPL-3.0), so anyone can check these promises.

Website: [studycycle.app](https://studycycle.app)

## What it does

- A focus timer and a break timer, with an alert when each one ends, even when the phone is locked.
- Presets: Deep focus (90 / 20 min, the default), Classic (50 / 10), Short (25 / 5), or Custom.
- A break idea each break (stretch, water, rest your eyes…), so breaks happen away from the screen.
- Optional: start the next focus block automatically. After 3 automatic starts in a row it waits
  for you, so a forgotten timer can't log study time all night.
- Optional: keep the screen on while the timer runs.
- Progress: today's focus time, a 7-day chart, a streak and all-time totals, stored only on the phone.
- Pause, resume, skip to the break, or end the session (time already studied is kept).
- Light and dark mode, screen-reader labels, and text that scales with system font size.

### The research, honestly

The 90-minute default comes from Kleitman's "basic rest-activity cycle" and from studies of
deliberate practice in which experts worked in sessions of about 60–90 minutes. A 2022
meta-analysis found that short breaks reduce fatigue. There is no proof that exactly 90 minutes is
best for everyone, and the app says so. The full references are on the app's About screen.

## How the timer works

The timer never counts down in memory. It saves **when the current phase ends**, so the right
state can always be worked out from the clock, even if the app was closed for hours, the phone
restarted, or the app was killed. Alerts are scheduled on the phone with the operating system's
own alarm service: no server and no push notifications.

```
mobile/                         Flutter app (Android + iOS)
  lib/
    main.dart, app.dart         Startup and root widget
    domain/                     Pure rules, fully unit-tested:
      timer_engine.dart           state machine (start, pause, resume, skip, stop, advance)
      timer_state.dart            the saved timer state
      phase_alerts.dart           which alerts to schedule
      study_history.dart          daily totals, 7-day view, streak
      cycle_plan.dart             presets and limits
    data/app_store.dart         Saves settings, timer and history on the device
    controller/                 Connects the rules to storage, alerts and the screen
    platform/                   Notifications and keep-screen-on (small native channel)
    ui/                         Screens and widgets
  android/.../MainActivity.kt   Keep-screen-on channel (a window flag, no permission)
  ios/Runner/AppDelegate.swift  Keep-screen-on channel and foreground alerts
  test/                         Unit, controller and widget tests
website/                        studycycle.app (static HTML/CSS, no scripts or trackers)
```

The app's name and logo, the screenshots and the website images are brand assets. They are kept
out of this repository and are not covered by the GPL.

## Building

Requirements: Flutter 3.41+ (Dart 3.11+). For iOS: Xcode on macOS.

```bash
cd mobile
flutter pub get
flutter analyze        # must report no issues
flutter test
flutter run            # on a device or emulator
```

For iOS, run `pod install` in `mobile/ios` once, then open `mobile/ios/Runner.xcworkspace` and
choose your own team and bundle ID under Signing & Capabilities.

Android release builds are signed with an upload key referenced from `mobile/android/key.properties`,
which is never committed. Building a Play bundle without it fails on purpose. To make your own
copy, see [Sign the app](https://docs.flutter.dev/deployment/android#sign-the-app).

## Privacy, verified

The Android release build has **no `INTERNET` permission**, so it cannot send or receive
anything. You can check this yourself:

```bash
aapt dump permissions build/app/outputs/flutter-apk/app-release.apk
```

See [PRIVACY.md](PRIVACY.md) for every permission and what it's for, and [SECURITY.md](SECURITY.md)
to report a problem.

## License

Copyright (C) 2026 BitDevelopers LLC

Study Cycle is free software: you can redistribute it and/or modify it under the terms of the
[GNU General Public License v3.0](LICENSE) as published by the Free Software Foundation.
Anyone who distributes a modified version must also share its source code under the same license.
