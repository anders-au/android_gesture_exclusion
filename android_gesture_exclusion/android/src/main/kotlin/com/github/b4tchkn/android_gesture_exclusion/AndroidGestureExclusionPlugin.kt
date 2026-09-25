package com.github.b4tchkn.android_gesture_exclusion

import android.app.Activity
import android.graphics.Rect
import androidx.core.view.ViewCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.lang.ref.WeakReference

/**
 * Excludes rects of the host Activity's window from the system gesture.
 *
 * The method-call handler is installed as soon as the plugin is attached to the
 * engine and stays installed for the lifetime of that engine. Calls that arrive
 * while no Activity is attached — a cached/retained engine that outlives its
 * Activity, or an engine started headless from a service — are acknowledged as
 * no-ops instead of failing with `MissingPluginException`.
 */
class AndroidGestureExclusionPlugin : FlutterPlugin, ActivityAware {
    companion object {
        private const val CHANNEL = "com.github.b4tchkn/android_gesture_exclusion"
    }

    private var methodChannel: MethodChannel? = null
    private var activityReference: WeakReference<Activity>? = null

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        val channel = MethodChannel(flutterPluginBinding.binaryMessenger, CHANNEL)
        // Registered here instead of in onAttachedToActivity so that a call made
        // while no Activity is attached resolves (and is ignored) rather than
        // throwing on the Dart side.
        channel.setMethodCallHandler(
            AndroidGestureExclusionMethodHandler { activityReference?.get() }
        )
        methodChannel = channel
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel?.setMethodCallHandler(null)
        methodChannel = null
        activityReference = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityReference = WeakReference(binding.activity)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activityReference = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activityReference = WeakReference(binding.activity)
    }

    override fun onDetachedFromActivity() {
        activityReference = null
    }
}

private class AndroidGestureExclusionMethodHandler(
    private val activityProvider: () -> Activity?,
) : MethodChannel.MethodCallHandler {
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "setSystemGestureExclusionRects" -> {
                val activity = activityProvider()
                if (activity == null) {
                    // No Activity is attached to the engine, so there is no window
                    // to exclude rects from and nothing to update. Report success:
                    // callers are layout/visibility callbacks that must never see
                    // a platform failure.
                    result.success(null)
                    return
                }
                val arguments = call.arguments as? List<*> ?: emptyList<Any?>()
                val decodedRects = decodeExclusionRects(arguments)
                ViewCompat.setSystemGestureExclusionRects(
                    activity.window.decorView,
                    decodedRects
                )
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    /**
     * Decodes `{left, top, right, bottom}` maps, ignoring entries that are not
     * well-formed instead of failing the whole call.
     */
    private fun decodeExclusionRects(inputRects: List<*>): List<Rect> =
        inputRects.mapNotNull { item ->
            val encoded = item as? Map<*, *> ?: return@mapNotNull null
            val left = encoded["left"] as? Number ?: return@mapNotNull null
            val top = encoded["top"] as? Number ?: return@mapNotNull null
            val right = encoded["right"] as? Number ?: return@mapNotNull null
            val bottom = encoded["bottom"] as? Number ?: return@mapNotNull null
            Rect(left.toInt(), top.toInt(), right.toInt(), bottom.toInt())
        }
}
