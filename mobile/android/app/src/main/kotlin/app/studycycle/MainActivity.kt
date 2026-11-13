package app.studycycle

import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * The single Android activity that hosts the Flutter UI.
 *
 * Besides the Flutter defaults it answers one platform channel, [SCREEN_CHANNEL], which lets the
 * app keep the screen on while a study timer runs (the user can turn this off in Settings).
 * Keeping the screen on uses a window flag, so it needs no permission.
 */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SCREEN_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setKeepScreenOn" -> {
                        val keepOn = call.argument<Boolean>("on") == true
                        if (keepOn) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private companion object {
        /** Must match `ScreenAwake.channelName` in lib/platform/screen_awake.dart. */
        const val SCREEN_CHANNEL = "app.studycycle/screen"
    }
}
