/// The root widget.
library;

import 'package:flutter/material.dart';

import 'app_info.dart';
import 'controller/study_controller.dart';
import 'ui/brand.dart';
import 'ui/screens/home_screen.dart';

/// The Study Cycle app. Follows the system light or dark mode.
class StudyCycleApp extends StatelessWidget {
  /// Creates the app around a loaded [controller].
  const StudyCycleApp({required this.controller, super.key});

  /// The app's state.
  final StudyController controller;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: AppInfo.name,
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    darkTheme: AppTheme.dark,
    home: HomeScreen(controller: controller),
  );
}
