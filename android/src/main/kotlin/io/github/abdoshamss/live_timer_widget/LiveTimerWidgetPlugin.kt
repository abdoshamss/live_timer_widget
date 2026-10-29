package io.github.abdoshamss.live_timer_widget

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/** The Dart side's door to [LiveTimerStore] and [LiveTimerWidgetProvider], and the tap relay. */
class LiveTimerWidgetPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler,
    ActivityAware,
    PluginRegistry.NewIntentListener {

    private lateinit var context: Context
    private lateinit var channel: MethodChannel
    private lateinit var tapChannel: EventChannel
    private var taps: EventChannel.EventSink? = null
    private var activity: ActivityPluginBinding? = null
    private var initialTap: Map<String, String?>? = null

    /** Disk and bitmap work stays off the platform thread, in call order. */
    private lateinit var io: ExecutorService
    private val main = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        io = Executors.newSingleThreadExecutor()
        channel = MethodChannel(binding.binaryMessenger, "live_timer_widget")
        channel.setMethodCallHandler(this)
        tapChannel = EventChannel(binding.binaryMessenger, "live_timer_widget/taps")
        tapChannel.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        tapChannel.setStreamHandler(null)
        io.shutdown()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            // The App Group and widget kind are iOS-only.
            "initialize" -> result.success(null)
            "load" -> background(result) { LiveTimerStore.load(context) }
            "save" -> background(result) {
                LiveTimerStore.save(context, call.argument<String>("state") ?: "")
                LiveTimerWidgetProvider.updateAll(context)
                null
            }
            "hasImage" -> background(result) {
                LiveTimerStore.image(context, call.argument<String>("name")!!).exists()
            }
            "saveImage" -> background(result) {
                LiveTimerStore.saveImage(context, call.argument<String>("name")!!, call.argument<ByteArray>("bytes")!!)
                null
            }
            "pruneImages" -> background(result) {
                LiveTimerStore.pruneImages(context, call.argument<List<String>>("keep")!!.toSet())
                null
            }
            "installedCount" -> result.success(LiveTimerWidgetProvider.installedIds(context).size)
            "isPinSupported" -> result.success(isPinSupported())
            "requestPin" -> result.success(
                isPinSupported() &&
                    AppWidgetManager.getInstance(context)
                        .requestPinAppWidget(LiveTimerWidgetProvider.componentName(context), null, null),
            )
            "initialTap" -> {
                result.success(initialTap)
                initialTap = null
            }
            else -> result.notImplemented()
        }
    }

    private fun isPinSupported(): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            AppWidgetManager.getInstance(context).isRequestPinAppWidgetSupported

    private fun background(result: MethodChannel.Result, work: () -> Any?) {
        io.execute {
            try {
                val value = work()
                main.post { result.success(value) }
            } catch (e: Exception) {
                main.post { result.error("live_timer_widget", e.message, null) }
            }
        }
    }

    // Taps ----------------------------------------------------------------

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        taps = events
    }

    override fun onCancel(arguments: Any?) {
        taps = null
    }

    override fun onNewIntent(intent: Intent): Boolean {
        val tap = consumeTap(intent) ?: return false
        taps?.success(tap)
        return true
    }

    /** The tap [intent] carries, once: it's marked so a recreated activity doesn't replay it. */
    private fun consumeTap(intent: Intent?): Map<String, String?>? {
        if (intent?.action != LiveTimerRenderer.ACTION_TAP || intent.getBooleanExtra(EXTRA_CONSUMED, false)) {
            return null
        }
        intent.putExtra(EXTRA_CONSUMED, true)
        return mapOf(
            "link" to intent.getStringExtra(LiveTimerRenderer.EXTRA_LINK),
            "target" to (intent.getStringExtra(LiveTimerRenderer.EXTRA_TARGET) ?: LiveTimerRenderer.TARGET_WIDGET),
        )
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        attach(binding)
        consumeTap(binding.activity.intent)?.let { initialTap = it }
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = attach(binding)

    override fun onDetachedFromActivityForConfigChanges() = detach()

    override fun onDetachedFromActivity() = detach()

    private fun attach(binding: ActivityPluginBinding) {
        activity = binding
        binding.addOnNewIntentListener(this)
    }

    private fun detach() {
        activity?.removeOnNewIntentListener(this)
        activity = null
    }

    private companion object {
        const val EXTRA_CONSUMED = "live_timer_widget.consumed"
    }
}
