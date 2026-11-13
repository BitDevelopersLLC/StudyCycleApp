/// Short ideas for a good break, shown on the timer screen while resting.
library;

/// The break suggestions, in the order they rotate.
abstract final class BreakTips {
  /// Every tip. Each one is something that moves you away from the screen.
  static const List<String> all = <String>[
    'Stand up and stretch your back, neck and shoulders.',
    'Drink a glass of water.',
    'Look at something far away for a minute to rest your eyes.',
    'Take a short walk, even just around the room.',
    'Close your eyes and take ten slow breaths.',
    'Step outside or open a window for some fresh air.',
    'Have a healthy snack.',
    'Put your phone down. Let your mind wander.',
  ];

  /// The tip for the break after [completedCycles] focus blocks. A new one each break.
  /// Dart's `%` never returns a negative number here, so 0 cycles also works.
  static String forCycle(int completedCycles) => all[(completedCycles - 1) % all.length];
}
