/// Works out which notifications to schedule for a running timer. Pure, so it is unit-tested.
library;

import 'timer_engine.dart';
import 'timer_state.dart';

/// One notification to show when a phase ends.
class PhaseAlert {
  /// Creates an alert shown at [at].
  const PhaseAlert({required this.at, required this.title, required this.body});

  /// When to show it (UTC).
  final DateTime at;

  /// The notification title.
  final String title;

  /// The notification text.
  final String body;

  @override
  String toString() => 'PhaseAlert($at, $title)';
}

/// Plans the notifications for the phases ahead.
abstract final class PhaseAlertPlanner {
  /// The most alerts scheduled at once. iOS allows 64 pending notifications per app.
  static const int maxAlerts = 12;

  /// The alerts for every phase end coming up from [state], following [rules] the same way
  /// `TimerEngine.advance` would. Returns an empty list unless the timer is running.
  static List<PhaseAlert> plan(TimerState state, TimerRules rules) {
    final alerts = <PhaseAlert>[];
    var current = state;
    while (current.status == TimerStatus.running && alerts.length < maxAlerts) {
      final endsAt = current.phaseEndsAt!;
      final next = TimerEngine.advance(current, rules, endsAt).state;
      alerts.add(_alertFor(current, next, endsAt));
      current = next;
    }
    return alerts;
  }

  static PhaseAlert _alertFor(TimerState ending, TimerState next, DateTime at) {
    if (ending.phase == Phase.focus) {
      final minutes = next.phaseLength.inMinutes;
      final cycles = next.completedCycles;
      return PhaseAlert(
        at: at,
        title: 'Focus done. Time for a break',
        body:
            'Cycle $cycles complete. Rest for $minutes ${minutes == 1 ? 'minute' : 'minutes'}: '
            'stand up, stretch, drink some water.',
      );
    }
    if (next.status == TimerStatus.running) {
      return PhaseAlert(
        at: at,
        title: 'Break over. Focus started',
        body: 'Your next ${next.phaseLength.inMinutes}-minute focus block has begun.',
      );
    }
    return PhaseAlert(
      at: at,
      title: 'Break over',
      body: 'Open Study Cycle when you are ready for the next focus block.',
    );
  }
}
