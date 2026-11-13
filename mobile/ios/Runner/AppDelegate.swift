import Flutter
import UIKit
import UserNotifications

/// The iOS application delegate.
///
/// Besides the Flutter defaults it makes the app the notification center's delegate, so phase
/// alerts also show while the app is open, and it answers one platform channel
/// (`app.studycycle/screen`) that keeps the screen awake while a study timer runs.
@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// Must match `ScreenAwake.channelName` in lib/platform/screen_awake.dart.
  private static let screenChannel = "app.studycycle/screen"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ScreenAwake") else {
      return
    }
    let channel = FlutterMethodChannel(
      name: AppDelegate.screenChannel, binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      guard call.method == "setKeepScreenOn" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let args = call.arguments as? [String: Any]
      let keepOn = args?["on"] as? Bool ?? false
      DispatchQueue.main.async {
        UIApplication.shared.isIdleTimerDisabled = keepOn
        result(nil)
      }
    }
  }
}
