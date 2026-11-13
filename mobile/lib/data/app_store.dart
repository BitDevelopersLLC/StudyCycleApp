/// Saves the timer, settings and study history on the device. Nothing is ever sent anywhere.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/cycle_plan.dart';
import '../domain/study_history.dart';
import '../domain/timer_state.dart';

/// The small key-value interface the app needs, so tests can use [MemoryKeyValueStore].
abstract interface class KeyValueStore {
  /// The string saved under [key], or null.
  String? getString(String key);

  /// Saves [value] under [key].
  Future<void> setString(String key, String value);

  /// The bool saved under [key], or null.
  bool? getBool(String key);

  /// Saves [value] under [key].
  Future<void> setBool(String key, bool value);

  /// The int saved under [key], or null.
  int? getInt(String key);

  /// Saves [value] under [key].
  Future<void> setInt(String key, int value);

  /// Deletes [key].
  Future<void> remove(String key);
}

/// [KeyValueStore] backed by the platform's app preferences
/// (SharedPreferences on Android, NSUserDefaults on iOS).
class PreferencesKeyValueStore implements KeyValueStore {
  /// Wraps an open [SharedPreferences].
  PreferencesKeyValueStore(this._prefs);

  /// Opens the app's preferences.
  static Future<PreferencesKeyValueStore> open() async =>
      PreferencesKeyValueStore(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;

  @override
  String? getString(String key) => _prefs.getString(key);

  @override
  Future<void> setString(String key, String value) => _prefs.setString(key, value);

  @override
  bool? getBool(String key) => _prefs.getBool(key);

  @override
  Future<void> setBool(String key, bool value) => _prefs.setBool(key, value);

  @override
  int? getInt(String key) => _prefs.getInt(key);

  @override
  Future<void> setInt(String key, int value) => _prefs.setInt(key, value);

  @override
  Future<void> remove(String key) => _prefs.remove(key);
}

/// An in-memory [KeyValueStore] for tests.
class MemoryKeyValueStore implements KeyValueStore {
  /// Creates an empty store, or one holding [values].
  MemoryKeyValueStore([Map<String, Object>? values]) : values = values ?? <String, Object>{};

  /// Everything saved so far.
  final Map<String, Object> values;

  @override
  String? getString(String key) => values[key] as String?;

  @override
  Future<void> setString(String key, String value) async => values[key] = value;

  @override
  bool? getBool(String key) => values[key] as bool?;

  @override
  Future<void> setBool(String key, bool value) async => values[key] = value;

  @override
  int? getInt(String key) => values[key] as int?;

  @override
  Future<void> setInt(String key, int value) async => values[key] = value;

  @override
  Future<void> remove(String key) async => values.remove(key);
}

/// The user's choices from the Settings screen.
class AppSettings {
  /// Creates settings.
  const AppSettings({required this.plan, this.autoStartFocus = false, this.keepScreenOn = true});

  /// Focus and break lengths.
  final CyclePlan plan;

  /// Whether the next focus block starts by itself after a break.
  final bool autoStartFocus;

  /// Whether the screen stays on while the timer runs and the app is open.
  final bool keepScreenOn;

  /// A copy with the given fields changed.
  AppSettings copyWith({CyclePlan? plan, bool? autoStartFocus, bool? keepScreenOn}) => AppSettings(
    plan: plan ?? this.plan,
    autoStartFocus: autoStartFocus ?? this.autoStartFocus,
    keepScreenOn: keepScreenOn ?? this.keepScreenOn,
  );
}

/// Typed loading and saving on top of a [KeyValueStore]. Damaged data falls back to defaults.
class AppStore {
  /// Creates a store over [_kv].
  AppStore(this._kv);

  final KeyValueStore _kv;

  static const String _timerKey = 'timer.v1';
  static const String _historyKey = 'history.v1';
  static const String _presetKey = 'plan.preset';
  static const String _focusKey = 'plan.focusMinutes';
  static const String _breakKey = 'plan.breakMinutes';
  static const String _autoStartKey = 'settings.autoStartFocus';
  static const String _keepScreenOnKey = 'settings.keepScreenOn';
  static const String _askedForAlertsKey = 'alerts.asked';

  /// The saved timer, or [TimerState.idle].
  TimerState loadTimer() => TimerState.fromJson(_decode(_kv.getString(_timerKey)));

  /// Saves [state].
  Future<void> saveTimer(TimerState state) => _kv.setString(_timerKey, jsonEncode(state.toJson()));

  /// The saved study history (empty on a new install).
  StudyHistory loadHistory() => StudyHistory.fromJson(_decode(_kv.getString(_historyKey)));

  /// Saves [history].
  Future<void> saveHistory(StudyHistory history) =>
      _kv.setString(_historyKey, jsonEncode(history.toJson()));

  /// Deletes the study history.
  Future<void> clearHistory() => _kv.remove(_historyKey);

  /// Whether the app has already asked for notification permission.
  bool loadAskedForAlerts() => _kv.getBool(_askedForAlertsKey) ?? false;

  /// Remembers that the app asked for notification permission.
  Future<void> saveAskedForAlerts() => _kv.setBool(_askedForAlertsKey, true);

  /// The saved settings, or the defaults.
  AppSettings loadSettings() {
    final preset = CyclePreset.fromName(_kv.getString(_presetKey));
    final plan = CyclePlan(
      preset: preset,
      focusMinutes: _kv.getInt(_focusKey) ?? preset.focusMinutes,
      breakMinutes: _kv.getInt(_breakKey) ?? preset.breakMinutes,
    );
    return AppSettings(
      plan: plan,
      autoStartFocus: _kv.getBool(_autoStartKey) ?? false,
      keepScreenOn: _kv.getBool(_keepScreenOnKey) ?? true,
    );
  }

  /// Saves [settings].
  Future<void> saveSettings(AppSettings settings) async {
    await _kv.setString(_presetKey, settings.plan.preset.name);
    await _kv.setInt(_focusKey, settings.plan.focusMinutes);
    await _kv.setInt(_breakKey, settings.plan.breakMinutes);
    await _kv.setBool(_autoStartKey, settings.autoStartFocus);
    await _kv.setBool(_keepScreenOnKey, settings.keepScreenOn);
  }

  static Map<String, Object?>? _decode(String? raw) {
    if (raw == null) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, Object?> ? decoded : null;
    } on FormatException {
      return null;
    }
  }
}
