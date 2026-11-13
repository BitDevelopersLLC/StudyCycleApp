# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project
uses [Semantic Versioning](https://semver.org/).

## [1.0.0] - Unreleased

A complete rewrite in Flutter. The earlier Xamarin app (2023) is no longer maintained; its code is
kept in the git history under the tag `xamarin-template-2023`.

### Added
- Focus and break timer with presets: Deep focus (90 / 20 min, default), Classic (50 / 10),
  Short (25 / 5) and Custom (5–180 min focus, 1–60 min break).
- Alerts when a focus block or break ends, scheduled on the device and delivered while the phone
  is locked. On Android, a prompt to allow on-time alerts ("Alarms & reminders").
- The timer survives the app being closed or the phone restarting.
- Optional automatic start of the next focus block, which pauses after 3 automatic starts in a row.
- Optional keep-the-screen-on while the timer runs.
- Break ideas shown during each break.
- Progress screen: today, the last 7 days, streak and all-time totals, with a delete option.
- About screen with the research behind the cycle lengths and its limits, and the privacy promise.
- Light and dark mode; screen reader labels.
- iPad and tablet layout: every screen is a centered column instead of stretching edge to edge.
- The Study Cycle owl logo as the app icon (with an Android themed icon) and as the notification icon.
- No data collection; no internet permission on Android.
