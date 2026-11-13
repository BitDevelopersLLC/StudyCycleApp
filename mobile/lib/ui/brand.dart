/// Study Cycle's colors, themes and text formatting helpers.
library;

import 'package:flutter/material.dart';

import '../domain/timer_state.dart';

/// The brand colors from the original Study Cycle design: green for focus, blue for rest and
/// orange for paused. The darker shades are used behind white text so it meets WCAG AA contrast.
abstract final class BrandColors {
  /// Focus green (logo and accents).
  static const Color focus = Color(0xFF5DB075);

  /// Darker focus green, for buttons with white text.
  static const Color focusDark = Color(0xFF2F7A4A);

  /// Rest blue (logo and accents).
  static const Color rest = Color(0xFF3E92CC);

  /// Darker rest blue, for buttons with white text.
  static const Color restDark = Color(0xFF1F6FA8);

  /// Paused orange.
  static const Color paused = Color(0xFFFFA279);

  /// Darker paused orange, for buttons with white text.
  static const Color pausedDark = Color(0xFFB4532A);
}

/// The light and dark themes.
abstract final class AppTheme {
  /// The light theme.
  static ThemeData get light => _build(Brightness.light);

  /// The dark theme.
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) => ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: BrandColors.rest, brightness: brightness),
    useMaterial3: true,
  );
}

/// The accent color for the timer in [state]. Lighter shades in dark mode.
Color phaseColor(TimerState state, Brightness brightness) {
  final dark = brightness == Brightness.dark;
  if (state.status == TimerStatus.paused) {
    return dark ? BrandColors.paused : BrandColors.pausedDark;
  }
  // Waiting means the next step is a focus block, so it uses the focus color too.
  if (state.status == TimerStatus.idle ||
      state.status == TimerStatus.waiting ||
      state.phase == Phase.focus) {
    return dark ? BrandColors.focus : BrandColors.focusDark;
  }
  return dark ? BrandColors.rest : BrandColors.restDark;
}

/// A countdown like `1:29:59` or `19:59`. Rounds up, so the display never shows 0:00 early.
String formatCountdown(Duration remaining) {
  final totalSeconds = (remaining.inMilliseconds / 1000).ceil();
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:$seconds';
  }
  return '$minutes:$seconds';
}

/// A study total like `2 h 05 min`, `45 min` or `0 min`.
String formatStudyTime(Duration time) {
  final hours = time.inHours;
  final minutes = time.inMinutes % 60;
  if (hours == 0) {
    return '$minutes min';
  }
  return '$hours h ${minutes.toString().padLeft(2, '0')} min';
}

/// The countdown read aloud by screen readers, like "19 minutes 59 seconds left".
String spokenCountdown(Duration remaining) {
  final totalSeconds = (remaining.inMilliseconds / 1000).ceil();
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  final parts = <String>[
    if (hours > 0) '$hours ${hours == 1 ? 'hour' : 'hours'}',
    if (minutes > 0) '$minutes ${minutes == 1 ? 'minute' : 'minutes'}',
    if (seconds > 0 || totalSeconds == 0) '$seconds ${seconds == 1 ? 'second' : 'seconds'}',
  ];
  return '${parts.join(' ')} left';
}
