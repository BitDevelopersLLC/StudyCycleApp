/// Keeps the screen from turning off while a study timer runs.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Turns "keep the screen on" on or off.
abstract interface class ScreenAwake {
  /// Keeps the screen on when [on] is true, and restores normal sleep when false.
  Future<void> setKeepScreenOn({required bool on});
}

/// [ScreenAwake] over a small native channel: a window flag on Android and
/// `isIdleTimerDisabled` on iOS. Neither needs a permission.
class PlatformScreenAwake implements ScreenAwake {
  /// The channel name. Must match MainActivity.kt and AppDelegate.swift.
  static const String channelName = 'app.studycycle/screen';

  static const MethodChannel _channel = MethodChannel(channelName);

  bool? _current;

  @override
  Future<void> setKeepScreenOn({required bool on}) async {
    if (_current == on) {
      return;
    }
    _current = on;
    try {
      await _channel.invokeMethod<void>('setKeepScreenOn', <String, bool>{'on': on});
    } on PlatformException catch (error) {
      // Not being able to keep the screen on is harmless; the timer still works.
      debugPrint('Keep screen on failed: ${error.message}');
    } on MissingPluginException {
      // Platforms without the channel (tests, unsupported OS).
    }
  }
}
