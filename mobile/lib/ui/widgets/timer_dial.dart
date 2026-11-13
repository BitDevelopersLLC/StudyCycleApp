/// The round countdown display.
library;

import 'package:flutter/material.dart';

import '../../domain/cycle_plan.dart';
import '../../domain/timer_state.dart';
import '../brand.dart';

/// A progress ring with the time left, the phase name and the cycle number.
class TimerDial extends StatelessWidget {
  /// Creates a dial for [state] at [now].
  const TimerDial({
    required this.state,
    required this.plan,
    required this.now,
    required this.color,
    super.key,
  });

  /// The timer to show.
  final TimerState state;

  /// The plan, used to show the focus length before a session starts.
  final CyclePlan plan;

  /// The current time.
  final DateTime now;

  /// The ring and text color.
  final Color color;

  /// The dial's width and height on phones, in logical pixels.
  static const phoneSize = 260.0;

  /// The dial's width and height on tablets, in logical pixels.
  static const tabletSize = 400.0;

  /// Screens whose shortest side is at least this wide (every iPad) get the tablet size.
  static const tabletBreakpoint = 600.0;

  /// The dial size for a screen of [screen] logical pixels.
  static double sizeFor(Size screen) =>
      screen.shortestSide >= tabletBreakpoint ? tabletSize : phoneSize;

  /// The phase name shown above the countdown.
  static String phaseLabel(TimerState state) => switch (state.status) {
    TimerStatus.idle => 'Ready',
    TimerStatus.waiting => 'Break over',
    TimerStatus.paused => state.phase == Phase.focus ? 'Focus paused' : 'Break paused',
    TimerStatus.running => state.phase == Phase.focus ? 'Focus' : 'Break',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final remaining = switch (state.status) {
      TimerStatus.idle || TimerStatus.waiting => plan.focus,
      _ => state.remainingAt(now),
    };
    final progress = state.status == TimerStatus.idle ? 0.0 : state.progressAt(now);
    final cycleNumber = state.completedCycles + (state.phase == Phase.focus ? 1 : 0);
    final label = phaseLabel(state);
    final size = sizeFor(MediaQuery.sizeOf(context));
    // The ring, stroke and text all grow by the same factor on tablets.
    final scale = size / phoneSize;
    TextStyle? scaled(TextStyle? style) =>
        style?.copyWith(fontSize: style.fontSize == null ? null : style.fontSize! * scale);

    return Semantics(
      label: '$label. ${spokenCountdown(remaining)}.',
      liveRegion: false,
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CircularProgressIndicator(
              value: progress,
              strokeWidth: 12 * scale,
              strokeCap: StrokeCap.round,
              color: color,
              backgroundColor: color.withValues(alpha: 0.15),
            ),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label, style: scaled(theme.textTheme.titleMedium)?.copyWith(color: color)),
                  FittedBox(
                    child: Text(
                      formatCountdown(remaining),
                      style: scaled(theme.textTheme.displayLarge)?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  if (state.isActive)
                    Text(
                      state.status == TimerStatus.waiting
                          ? '${state.completedCycles} done'
                          : 'Cycle $cycleNumber',
                      style: scaled(theme.textTheme.bodyMedium),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
