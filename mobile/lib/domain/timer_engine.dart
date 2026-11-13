/// Pure rules for moving the study timer between states. No clocks, storage or plugins here:
/// every function takes the current time as an argument, so it is fully unit-tested.
library;

import 'cycle_plan.dart';
import 'timer_state.dart';

/// The user's settings that decide how the timer moves from one phase to the next.
class TimerRules {
  /// Creates rules for a [plan].
  const TimerRules({required this.plan, this.autoStartFocus = false});

  /// Lengths of focus blocks and breaks.
  final CyclePlan plan;

  /// Whether the next focus block starts by itself when a break ends.
  ///
  /// Even when true, the timer waits for the user after [maxAutoStarts] focus blocks in a row
  /// have started without a tap. This stops a forgotten timer from logging study time all night.
  final bool autoStartFocus;

  /// How many focus blocks in a row may start automatically before the timer waits.
  static const int maxAutoStarts = 3;
}

/// A phase that ended, used to update the study history.
class CompletedPhase {
  /// Records that a [phase] lasting [duration] ended at [endedAt].
  const CompletedPhase({
    required this.phase,
    required this.duration,
    required this.endedAt,
    required this.finished,
  });

  /// Which phase ended.
  final Phase phase;

  /// How long the phase actually ran (less than planned if skipped or stopped early).
  final Duration duration;

  /// When the phase ended (UTC).
  final DateTime endedAt;

  /// True if the phase ran its full planned length.
  final bool finished;

  @override
  String toString() => 'CompletedPhase(${phase.name}, $duration, finished: $finished)';
}

/// The result of a timer action: the new state and any phases that ended along the way.
class TimerUpdate {
  /// Creates an update.
  const TimerUpdate(this.state, [this.completed = const <CompletedPhase>[]]);

  /// The timer after the action.
  final TimerState state;

  /// Phases that ended, oldest first.
  final List<CompletedPhase> completed;
}

/// The timer's state machine. Each action first catches up with [now], then applies itself.
abstract final class TimerEngine {
  /// Catches the timer up to [now]: ends every phase whose end time has passed and starts the
  /// next one where the rules allow. Call this whenever the app shows or saves the timer.
  static TimerUpdate advance(TimerState state, TimerRules rules, DateTime now) {
    var current = state;
    final completed = <CompletedPhase>[];
    while (current.status == TimerStatus.running && !now.isBefore(current.phaseEndsAt!)) {
      final endedAt = current.phaseEndsAt!;
      completed.add(
        CompletedPhase(
          phase: current.phase,
          duration: current.phaseLength,
          endedAt: endedAt,
          finished: true,
        ),
      );
      current = _next(current, rules, endedAt, byUser: false);
    }
    return TimerUpdate(current, completed);
  }

  /// Starts a focus block at [now] from [TimerStatus.idle] or [TimerStatus.waiting].
  /// Does nothing to a running or paused timer.
  static TimerUpdate start(TimerState state, TimerRules rules, DateTime now) {
    final caughtUp = advance(state, rules, now);
    final current = caughtUp.state;
    if (current.status == TimerStatus.running || current.status == TimerStatus.paused) {
      return caughtUp;
    }
    final cycles = current.status == TimerStatus.idle ? 0 : current.completedCycles;
    return TimerUpdate(_running(Phase.focus, rules.plan.focus, now, cycles), caughtUp.completed);
  }

  /// Puts a running timer on hold at [now], keeping the time left.
  static TimerUpdate pause(TimerState state, TimerRules rules, DateTime now) {
    final caughtUp = advance(state, rules, now);
    final current = caughtUp.state;
    if (current.status != TimerStatus.running) {
      return caughtUp;
    }
    final paused = TimerState(
      status: TimerStatus.paused,
      phase: current.phase,
      completedCycles: current.completedCycles,
      phaseLength: current.phaseLength,
      remaining: current.remainingAt(now),
    );
    return TimerUpdate(paused, caughtUp.completed);
  }

  /// Continues a paused timer at [now] with the time it had left.
  static TimerUpdate resume(TimerState state, TimerRules rules, DateTime now) {
    if (state.status != TimerStatus.paused) {
      return advance(state, rules, now);
    }
    return TimerUpdate(
      TimerState(
        status: TimerStatus.running,
        phase: state.phase,
        completedCycles: state.completedCycles,
        phaseLength: state.phaseLength,
        phaseEndsAt: now.toUtc().add(state.remaining),
      ),
    );
  }

  /// Ends the current phase early at [now] and moves on: focus goes to a break, and a break goes
  /// straight to focus (the user asked for it, so there is no waiting).
  ///
  /// [expected] is the phase the user was looking at. If that phase already ended by itself
  /// (the tap landed right at the boundary), only the catch-up happens, so a tap on "Start break
  /// now" can never skip the break that just began.
  static TimerUpdate skip(TimerState state, TimerRules rules, DateTime now, {Phase? expected}) {
    final caughtUp = advance(state, rules, now);
    final current = caughtUp.state;
    if (expected != null && caughtUp.completed.isNotEmpty) {
      return caughtUp;
    }
    switch (current.status) {
      case TimerStatus.idle:
        return caughtUp;
      case TimerStatus.waiting:
        return start(current, rules, now);
      case TimerStatus.running:
      case TimerStatus.paused:
        final ended = _endEarly(current, now);
        final next = _next(current, rules, now.toUtc(), byUser: true);
        return TimerUpdate(next, [...caughtUp.completed, ended]);
    }
  }

  /// Ends the session at [now]. Time already spent in the current phase is still reported.
  static TimerUpdate stop(TimerState state, TimerRules rules, DateTime now) {
    final caughtUp = advance(state, rules, now);
    final current = caughtUp.state;
    final completed = [...caughtUp.completed];
    if (current.status == TimerStatus.running || current.status == TimerStatus.paused) {
      final ended = _endEarly(current, now);
      if (ended.duration > Duration.zero) {
        completed.add(ended);
      }
    }
    return TimerUpdate(TimerState.idle, completed);
  }

  static CompletedPhase _endEarly(TimerState state, DateTime now) {
    final spent = state.phaseLength - state.remainingAt(now);
    return CompletedPhase(
      phase: state.phase,
      duration: spent.isNegative ? Duration.zero : spent,
      endedAt: now.toUtc(),
      finished: false,
    );
  }

  /// The state that follows [state] when its phase ends at [at].
  static TimerState _next(TimerState state, TimerRules rules, DateTime at, {required bool byUser}) {
    if (state.phase == Phase.focus) {
      return _running(
        Phase.rest,
        rules.plan.rest,
        at,
        state.completedCycles + 1,
        autoStarts: state.autoStarts,
      );
    }
    if (byUser) {
      return _running(Phase.focus, rules.plan.focus, at, state.completedCycles);
    }
    if (rules.autoStartFocus && state.autoStarts < TimerRules.maxAutoStarts) {
      return _running(
        Phase.focus,
        rules.plan.focus,
        at,
        state.completedCycles,
        autoStarts: state.autoStarts + 1,
      );
    }
    return TimerState(
      status: TimerStatus.waiting,
      phase: Phase.rest,
      completedCycles: state.completedCycles,
      phaseLength: Duration.zero,
    );
  }

  static TimerState _running(
    Phase phase,
    Duration length,
    DateTime from,
    int cycles, {
    int autoStarts = 0,
  }) => TimerState(
    status: TimerStatus.running,
    phase: phase,
    completedCycles: cycles,
    phaseLength: length,
    phaseEndsAt: from.toUtc().add(length),
    autoStarts: autoStarts,
  );
}
