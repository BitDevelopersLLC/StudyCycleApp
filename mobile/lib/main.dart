import 'package:flutter/material.dart';

import 'app.dart';
import 'controller/study_controller.dart';
import 'data/app_store.dart';
import 'platform/phase_notifier.dart';
import 'platform/screen_awake.dart';

/// Opens local storage and notifications, loads the saved timer and starts the app.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final notifier = LocalPhaseNotifier();
  await notifier.initialize();
  final controller = StudyController(
    store: AppStore(await PreferencesKeyValueStore.open()),
    notifier: notifier,
    screenAwake: PlatformScreenAwake(),
  );
  await controller.load();
  runApp(StudyCycleApp(controller: controller));
}
