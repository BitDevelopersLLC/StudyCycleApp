/// The saved state of the study timer.
///
/// The timer never counts down in memory. It stores the moment the current phase ends, so the
/// right state can always be worked out from the clock, even after the app was closed for hours.
library;

/// The two kinds of time in a study cycle.
enum Phase {
  /// Studying.
  focus,

  /// Resting between focus blocks.
  rest,
}

/// What the timer is doing.
enum TimerStatus {
  /// No session in progress.
  idle,

  /// A phase is counting down toward [TimerState.phaseEndsAt].
  running,

  /// A phase is on hold with [TimerState.remaining] left.
  paused,

  /// A break has finished and the next focus block is waiting for the user to start it.
  waiting,
}

/// An immutable snapshot of the timer. Use `TimerEngine` to move between states.
class TimerState {
  /// Creates a state. Prefer the named constructors and `TimerEngine`.
  const TimerState({
    required this.status,
    required this.phase,
    required this.completedCycles,
    required this.phaseLength,
    this.phaseEndsAt,
    this.remaining = Duration.zero,
    this.autoStarts = 0,
  });

  /// Restores a state saved with [toJson]. Returns [idle] if [json] is missing or damaged.
  factory TimerState.fromJson(Map<String, Object?>? json) {
    if (json == null) {
      return idle;
    }
    try {
      final status = TimerStatus.values.byName(json['status']! as String);
      final phase = Phase.values.byName(json['phase']! as String);
      final cycles = json['cycles']! as int;
      final lengthMs = json['lengthMs']! as int;
      final endsAtMs = json['endsAtMs'] as int?;
      final remainingMs = json['remainingMs'] as int? ?? 0;
      final autoStarts = json['autoStarts'] as int? ?? 0;
      final state = TimerState(
        status: status,
        phase: phase,
        completedCycles: cycles,
        phaseLength: Duration(milliseconds: lengthMs),
        phaseEndsAt: endsAtMs == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(endsAtMs, isUtc: true),
        remaining: Duration(milliseconds: remainingMs),
        autoStarts: autoStarts,
      );
      return state.isValid ? state : idle;
    } on Object {
      return idle;
    }
  }

  /// The state before any session has started.
  static const TimerState idle = TimerState(
    status: TimerStatus.idle,
    phase: Phase.focus,
    completedCycles: 0,
    phaseLength: Duration.zero,
  );

  /// What the timer is doing.
  final TimerStatus status;

  /// The current phase. When [status] is [TimerStatus.waiting], this is the break that ended.
  final Phase phase;

  /// How many focus blocks have been finished in this session.
  final int completedCycles;

  /// The full planned length of the current phase.
  final Duration phaseLength;

  /// When the current phase ends (UTC). Set only while [TimerStatus.running].
  final DateTime? phaseEndsAt;

  /// Time left in the current phase. Meaningful only while [TimerStatus.paused].
  final Duration remaining;

  /// How many focus blocks in a row started by themselves, with no tap from the user.
  /// See `TimerRules.maxAutoStarts`.
  final int autoStarts;

  /// True while a session is in progress (anything but [TimerStatus.idle]).
  bool get isActive => status != TimerStatus.idle;

  /// Whether the fields fit together. Saved data that fails this check is discarded.
  bool get isValid {
    if (completedCycles < 0 || autoStarts < 0 || phaseLength.isNegative || remaining.isNegative) {
      return false;
    }
    return switch (status) {
      TimerStatus.running => phaseEndsAt != null && phaseLength > Duration.zero,
      TimerStatus.paused => phaseLength > Duration.zero && remaining <= phaseLength,
      TimerStatus.idle || TimerStatus.waiting => true,
    };
  }

  /// Time left in the current phase at [now].
  Duration remainingAt(DateTime now) {
    switch (status) {
      case TimerStatus.running:
        final left = phaseEndsAt!.difference(now);
        return left.isNegative ? Duration.zero : left;
      case TimerStatus.paused:
        return remaining;
      case TimerStatus.idle:
      case TimerStatus.waiting:
        return Duration.zero;
    }
  }

  /// Share of the current phase already done at [now], from 0.0 to 1.0.
  double progressAt(DateTime now) {
    if (phaseLength <= Duration.zero) {
      return 0;
    }
    final done = phaseLength - remainingAt(now);
    return (done.inMilliseconds / phaseLength.inMilliseconds).clamp(0.0, 1.0);
  }

  /// A JSON-safe map for saving. Times are stored as UTC milliseconds.
  Map<String, Object?> toJson() => <String, Object?>{
    'status': status.name,
    'phase': phase.name,
    'cycles': completedCycles,
    'lengthMs': phaseLength.inMilliseconds,
    'endsAtMs': phaseEndsAt?.toUtc().millisecondsSinceEpoch,
    'remainingMs': remaining.inMilliseconds,
    'autoStarts': autoStarts,
  };

  @override
  bool operator ==(Object other) =>
      other is TimerState &&
      other.status == status &&
      other.phase == phase &&
      other.completedCycles == completedCycles &&
      other.phaseLength == phaseLength &&
      other.phaseEndsAt?.millisecondsSinceEpoch == phaseEndsAt?.millisecondsSinceEpoch &&
      other.remaining == remaining &&
      other.autoStarts == autoStarts;

  @override
  int get hashCode => Object.hash(
    status,
    phase,
    completedCycles,
    phaseLength,
    phaseEndsAt?.millisecondsSinceEpoch,
    remaining,
    autoStarts,
  );

  @override
  String toString() =>
      'TimerState(${status.name}, ${phase.name}, cycles: $completedCycles, '
      'length: $phaseLength, endsAt: $phaseEndsAt, remaining: $remaining, autoStarts: $autoStarts)';
}
