/// How long one study cycle lasts: a focus block followed by a break.
library;

/// The built-in cycle lengths the user can pick from, plus [custom].
enum CyclePreset {
  /// 90 minutes of focus and a 20-minute break, based on the ~90-minute rest-activity cycle.
  ultradian(label: 'Deep focus', focusMinutes: 90, breakMinutes: 20),

  /// 50 minutes of focus and a 10-minute break.
  classic(label: 'Classic', focusMinutes: 50, breakMinutes: 10),

  /// 25 minutes of focus and a 5-minute break, for warming up or tired days.
  short(label: 'Short', focusMinutes: 25, breakMinutes: 5),

  /// Lengths chosen by the user. The minutes here are only the starting values.
  custom(label: 'Custom', focusMinutes: 45, breakMinutes: 15);

  const CyclePreset({required this.label, required this.focusMinutes, required this.breakMinutes});

  /// The name shown in the app.
  final String label;

  /// The focus length this preset uses.
  final int focusMinutes;

  /// The break length this preset uses.
  final int breakMinutes;

  /// Looks up a preset by its [name], falling back to [ultradian] for unknown values.
  static CyclePreset fromName(String? name) =>
      CyclePreset.values.firstWhere((p) => p.name == name, orElse: () => CyclePreset.ultradian);
}

/// The focus and break lengths the timer uses. Immutable; values are always within the limits.
class CyclePlan {
  /// Creates a plan, clamping both lengths into the allowed ranges.
  CyclePlan({required this.preset, required int focusMinutes, required int breakMinutes})
    : focusMinutes = focusMinutes.clamp(minFocusMinutes, maxFocusMinutes),
      breakMinutes = breakMinutes.clamp(minBreakMinutes, maxBreakMinutes);

  /// The plan for one of the built-in presets.
  factory CyclePlan.fromPreset(CyclePreset preset) => CyclePlan(
    preset: preset,
    focusMinutes: preset.focusMinutes,
    breakMinutes: preset.breakMinutes,
  );

  /// The plan a new install starts with: [CyclePreset.ultradian].
  factory CyclePlan.standard() => CyclePlan.fromPreset(CyclePreset.ultradian);

  /// Shortest focus block allowed, in minutes.
  static const int minFocusMinutes = 5;

  /// Longest focus block allowed, in minutes.
  static const int maxFocusMinutes = 180;

  /// Shortest break allowed, in minutes.
  static const int minBreakMinutes = 1;

  /// Longest break allowed, in minutes.
  static const int maxBreakMinutes = 60;

  /// Which preset this plan came from ([CyclePreset.custom] if the user set the lengths).
  final CyclePreset preset;

  /// Length of each focus block, in minutes.
  final int focusMinutes;

  /// Length of each break, in minutes.
  final int breakMinutes;

  /// [focusMinutes] as a [Duration].
  Duration get focus => Duration(minutes: focusMinutes);

  /// [breakMinutes] as a [Duration].
  Duration get rest => Duration(minutes: breakMinutes);

  @override
  bool operator ==(Object other) =>
      other is CyclePlan &&
      other.preset == preset &&
      other.focusMinutes == focusMinutes &&
      other.breakMinutes == breakMinutes;

  @override
  int get hashCode => Object.hash(preset, focusMinutes, breakMinutes);

  @override
  String toString() => 'CyclePlan(${preset.name}, $focusMinutes/$breakMinutes)';
}
