import 'package:study_cycle/controller/study_controller.dart';
import 'package:study_cycle/data/app_store.dart';
import 'package:study_cycle/domain/phase_alerts.dart';
import 'package:study_cycle/platform/phase_notifier.dart';
import 'package:study_cycle/platform/screen_awake.dart';

/// A [PhaseNotifier] that records what the app asked for.
class FakeNotifier implements PhaseNotifier {
  /// The access the fake reports.
  AlertAccess access = AlertAccess.ready;

  /// The alerts currently "scheduled".
  List<PhaseAlert> scheduled = <PhaseAlert>[];

  /// How many times permission was requested.
  int requests = 0;

  /// How many times the exact-alarm settings were opened.
  int settingsOpened = 0;

  @override
  Future<void> initialize() async {}

  @override
  Future<AlertAccess> requestAccess() async {
    requests++;
    return access;
  }

  @override
  Future<AlertAccess> checkAccess() async => access;

  @override
  Future<void> openExactAlarmSettings() async => settingsOpened++;

  @override
  Future<void> schedule(List<PhaseAlert> alerts, {required DateTime now}) async {
    if (throwOnSchedule) {
      throw ArgumentError('scheduled date must be in the future');
    }
    scheduled = [
      for (final alert in alerts)
        if (!alert.at.isBefore(now.add(PhaseAlertPlanner.minimumLead))) alert,
    ];
  }

  /// When true, [schedule] throws like the plugin does for a time in the past.
  bool throwOnSchedule = false;

  @override
  Future<void> cancelPending() async => scheduled = <PhaseAlert>[];
}

/// A [ScreenAwake] that remembers the last request.
class FakeScreenAwake implements ScreenAwake {
  /// Whether the app last asked to keep the screen on.
  bool keptOn = false;

  @override
  Future<void> setKeepScreenOn({required bool on}) async => keptOn = on;
}

/// A clock the test moves by hand.
class FakeClock {
  /// Starts at [now].
  FakeClock(this.now);

  /// The current time.
  DateTime now;

  /// Moves the clock forward.
  void advance(Duration by) => now = now.add(by);

  /// The function to inject.
  DateTime call() => now;
}

/// Everything a controller test needs, wired together.
class Harness {
  /// Creates a harness at [start] (default: a fixed local morning).
  Harness({DateTime? start, Map<String, Object>? saved})
    : clock = FakeClock(start ?? DateTime(2026, 11, 12, 9)),
      kv = MemoryKeyValueStore(saved) {
    controller = StudyController(
      store: AppStore(kv),
      notifier: notifier,
      screenAwake: screen,
      clock: clock.call,
    );
  }

  /// The hand-moved clock.
  final FakeClock clock;

  /// The in-memory storage.
  final MemoryKeyValueStore kv;

  /// The fake notifications.
  final FakeNotifier notifier = FakeNotifier();

  /// The fake screen flag.
  final FakeScreenAwake screen = FakeScreenAwake();

  /// The controller under test.
  late final StudyController controller;
}
