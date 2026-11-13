/// Daily study totals and the numbers shown on the Progress screen. Pure, so it is unit-tested.
library;

import 'timer_engine.dart';
import 'timer_state.dart';

/// Focus time and finished cycles for one calendar day.
class DayTotal {
  /// Creates a total.
  const DayTotal({this.focus = Duration.zero, this.cycles = 0});

  /// Time spent in focus blocks that day.
  final Duration focus;

  /// Focus blocks that ran their full length that day.
  final int cycles;

  /// This total plus [other].
  DayTotal operator +(DayTotal other) =>
      DayTotal(focus: focus + other.focus, cycles: cycles + other.cycles);

  @override
  bool operator ==(Object other) =>
      other is DayTotal && other.focus == focus && other.cycles == cycles;

  @override
  int get hashCode => Object.hash(focus, cycles);

  @override
  String toString() => 'DayTotal($focus, $cycles cycles)';
}

/// The study history: one [DayTotal] per local calendar day. Immutable.
///
/// Only daily totals are kept: no subjects, notes or exact times. Days older than [keepDays]
/// are dropped.
class StudyHistory {
  /// Creates a history from totals keyed by [dayKey].
  StudyHistory([Map<String, DayTotal> days = const <String, DayTotal>{}])
    : days = Map<String, DayTotal>.unmodifiable(days);

  /// Restores a history saved with [toJson]. Bad entries are skipped.
  factory StudyHistory.fromJson(Map<String, Object?>? json) {
    final days = <String, DayTotal>{};
    for (final entry in (json ?? const <String, Object?>{}).entries) {
      final value = entry.value;
      if (!_dayKeyPattern.hasMatch(entry.key) || value is! List || value.length != 2) {
        continue;
      }
      final seconds = value[0];
      final cycles = value[1];
      if (seconds is int && cycles is int && seconds >= 0 && cycles >= 0) {
        days[entry.key] = DayTotal(
          focus: Duration(seconds: seconds),
          cycles: cycles,
        );
      }
    }
    return StudyHistory(days);
  }

  /// How many days of history are kept.
  static const int keepDays = 400;

  /// Focus sessions shorter than this are not recorded (a mis-tap, or a quick stop).
  static const Duration minimumFocus = Duration(minutes: 1);

  static final RegExp _dayKeyPattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  /// Totals keyed by local date, `yyyy-mm-dd`.
  final Map<String, DayTotal> days;

  /// The key for the local calendar day containing [time].
  static String dayKey(DateTime time) {
    final local = time.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '${local.year}-$month-$day';
  }

  /// A copy with the focus [phases] added (breaks are ignored), trimmed to [keepDays] before
  /// [now].
  StudyHistory record(Iterable<CompletedPhase> phases, DateTime now) {
    final updated = Map<String, DayTotal>.of(days);
    for (final phase in phases) {
      if (phase.phase != Phase.focus || phase.duration < minimumFocus) {
        continue;
      }
      // A block that crosses midnight is split between the days; the cycle counts on the day
      // it finished.
      final end = phase.endedAt.toLocal();
      var start = end.subtract(phase.duration);
      while (start.isBefore(end)) {
        final nextMidnight = DateTime(start.year, start.month, start.day + 1);
        final sliceEnd = nextMidnight.isBefore(end) ? nextMidnight : end;
        final finishesHere = sliceEnd == end;
        final key = dayKey(start);
        final added = DayTotal(
          focus: sliceEnd.difference(start),
          cycles: finishesHere && phase.finished ? 1 : 0,
        );
        updated[key] = (updated[key] ?? const DayTotal()) + added;
        start = sliceEnd;
      }
    }
    final oldestKept = dayKey(_daysBefore(now, keepDays - 1));
    updated.removeWhere((key, _) => key.compareTo(oldestKept) < 0);
    return StudyHistory(updated);
  }

  /// The total for the day containing [time].
  DayTotal dayOf(DateTime time) => days[dayKey(time)] ?? const DayTotal();

  /// Totals for the [count] days ending with the day of [now], oldest first.
  List<DayTotal> lastDays(DateTime now, int count) => [
    for (var i = count - 1; i >= 0; i--) dayOf(_daysBefore(now, i)),
  ];

  /// The sum of every recorded day.
  DayTotal get allTime => days.values.fold(const DayTotal(), (sum, day) => sum + day);

  /// Days in a row with at least one finished cycle, counting back from today. If today has no
  /// cycle yet, the streak counts back from yesterday so it is not lost before the day is over.
  int streak(DateTime now) {
    var offset = dayOf(now).cycles > 0 ? 0 : 1;
    var count = 0;
    while (dayOf(_daysBefore(now, offset)).cycles > 0) {
      count++;
      offset++;
    }
    return count;
  }

  /// A JSON-safe map for saving: `{"yyyy-mm-dd": [focusSeconds, cycles]}`.
  Map<String, Object?> toJson() => <String, Object?>{
    for (final entry in days.entries)
      entry.key: <int>[entry.value.focus.inSeconds, entry.value.cycles],
  };

  /// Noon on the local day [days] before [now]. Noon avoids daylight-saving edge cases.
  static DateTime _daysBefore(DateTime now, int days) {
    final local = now.toLocal();
    return DateTime(local.year, local.month, local.day - days, 12);
  }
}
