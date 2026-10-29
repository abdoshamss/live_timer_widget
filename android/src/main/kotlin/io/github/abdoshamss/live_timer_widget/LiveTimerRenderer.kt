package io.github.abdoshamss.live_timer_widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.BitmapShader
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Shader
import android.os.Bundle
import android.os.SystemClock
import android.text.TextUtils
import android.util.TypedValue
import android.view.View
import android.widget.RemoteViews
import java.util.Locale
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * Builds the widget's [RemoteViews] from a [Snapshot].
 *
 * The clock is a Chronometer, so it ticks every second inside the launcher
 * with no update from us. Everything a RemoteViews can't color on every API
 * level — the rounded background with its gradient, photo and scrim, and the
 * progress bar — is drawn into bitmaps sized to the widget.
 */
internal class LiveTimerRenderer(private val context: Context) {

    private val density = context.resources.displayMetrics.density

    fun render(state: WidgetState, snapshot: Snapshot, options: Bundle?): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.ltw_widget)
        val size = sizeOf(options)
        val compact = size.first < COMPACT_WIDTH_DP
        val rtl = state.rtl
            ?: (TextUtils.getLayoutDirectionFromLocale(Locale.getDefault()) == View.LAYOUT_DIRECTION_RTL)
        views.setInt(
            android.R.id.background,
            "setLayoutDirection",
            if (rtl) View.LAYOUT_DIRECTION_RTL else View.LAYOUT_DIRECTION_LTR,
        )

        val style = state.style
        val timer = state.timer
        val running = timer != null && snapshot.phase != Phase.IDLE
        val accent = snapshot.stage?.accent ?: timer?.accent?.takeIf { running } ?: style.accent
        val image = if (running) snapshot.stage?.image ?: timer?.image else state.idle?.image

        views.setImageViewBitmap(R.id.ltw_background, background(size, style, image, rtl))

        if (running) {
            bindRunning(views, timer!!, snapshot, style, accent, size, compact, rtl)
        } else {
            bindIdle(views, state.idle, style, accent, compact)
        }
        return views
    }

    private fun bindRunning(
        views: RemoteViews,
        timer: TimerSpec,
        snapshot: Snapshot,
        style: StyleSpec,
        accent: Int,
        size: Pair<Int, Int>,
        compact: Boolean,
        rtl: Boolean,
    ) {
        views.setViewVisibility(R.id.ltw_running, View.VISIBLE)
        views.setViewVisibility(R.id.ltw_idle, View.GONE)

        views.setTextViewText(R.id.ltw_title, snapshot.title)
        views.setTextColor(R.id.ltw_title, style.foreground)
        views.setInt(R.id.ltw_dot, "setColorFilter", accent)

        // A Chronometer counts from `elapsedRealtime`, not wall time.
        val now = SystemClock.elapsedRealtime()
        val base = if (snapshot.countingDown) now + snapshot.clockMs else now - snapshot.clockMs
        views.setChronometerCountDown(R.id.ltw_timer, snapshot.countingDown)
        views.setChronometer(R.id.ltw_timer, base, null, snapshot.ticking)
        views.setTextColor(R.id.ltw_timer, style.foreground)
        views.setTextViewTextSize(
            R.id.ltw_timer,
            TypedValue.COMPLEX_UNIT_SP,
            if (compact) TIMER_SP_COMPACT else TIMER_SP,
        )

        val progress = snapshot.progress
        val percent = progress?.let { "${(it * 100).toInt()}%" }
        views.setTextViewText(R.id.ltw_percent, percent ?: "")
        views.setTextColor(R.id.ltw_percent, accent)
        views.setViewVisibility(R.id.ltw_percent, if (percent == null) View.GONE else View.VISIBLE)

        val subtitle = snapshot.subtitle?.takeIf { it.isNotEmpty() && !compact }
        views.setTextViewText(R.id.ltw_subtitle, subtitle ?: "")
        views.setTextColor(R.id.ltw_subtitle, style.muted)
        views.setViewVisibility(R.id.ltw_subtitle, if (subtitle == null) View.GONE else View.VISIBLE)

        if (timer.showProgress && progress != null) {
            views.setViewVisibility(R.id.ltw_progress, View.VISIBLE)
            views.setImageViewBitmap(R.id.ltw_progress, progressBar(size, progress, accent, style.track, rtl))
        } else {
            views.setViewVisibility(R.id.ltw_progress, View.GONE)
        }

        views.setOnClickPendingIntent(android.R.id.background, tapIntent(timer.link, TARGET_WIDGET))
    }

    private fun bindIdle(
        views: RemoteViews,
        idle: IdleSpec?,
        style: StyleSpec,
        accent: Int,
        compact: Boolean,
    ) {
        views.setViewVisibility(R.id.ltw_running, View.GONE)
        views.setViewVisibility(R.id.ltw_idle, View.VISIBLE)
        // Stop the hidden chronometer so it doesn't tick for nothing.
        views.setChronometer(R.id.ltw_timer, SystemClock.elapsedRealtime(), null, false)

        // Until the app's first write, the layout's string resources show.
        idle?.title?.takeIf { it.isNotEmpty() }?.let { views.setTextViewText(R.id.ltw_idle_title, it) }
        views.setTextColor(R.id.ltw_idle_title, style.foreground)
        views.setTextViewTextSize(
            R.id.ltw_idle_title,
            TypedValue.COMPLEX_UNIT_SP,
            if (compact) IDLE_TITLE_SP_COMPACT else IDLE_TITLE_SP,
        )

        if (idle != null) {
            views.setTextViewText(R.id.ltw_idle_subtitle, idle.subtitle ?: "")
        }
        val hasSubtitle = !compact && (idle == null || !idle.subtitle.isNullOrEmpty())
        views.setViewVisibility(R.id.ltw_idle_subtitle, if (hasSubtitle) View.VISIBLE else View.GONE)
        views.setTextColor(R.id.ltw_idle_subtitle, style.muted)

        val action = idle?.actionLabel?.takeIf { it.isNotEmpty() }
        if (action != null) {
            views.setViewVisibility(R.id.ltw_idle_action, View.VISIBLE)
            views.setTextViewText(R.id.ltw_idle_action_label, action)
            views.setTextColor(R.id.ltw_idle_action_label, style.onAccent)
            views.setInt(R.id.ltw_idle_action_bg, "setColorFilter", accent)
            views.setOnClickPendingIntent(
                R.id.ltw_idle_action,
                tapIntent(idle.actionLink ?: idle.link, TARGET_ACTION),
            )
        } else {
            views.setViewVisibility(R.id.ltw_idle_action, View.GONE)
        }

        views.setOnClickPendingIntent(android.R.id.background, tapIntent(idle?.link, TARGET_WIDGET))
    }

    /**
     * Opens the app's launch activity with the tap in extras — not in the
     * intent's data, which Flutter's deep linking would route on its own.
     */
    private fun tapIntent(link: String?, target: String): PendingIntent {
        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?: Intent().setPackage(context.packageName)
        val intent = Intent(launch).apply {
            action = ACTION_TAP
            putExtra(EXTRA_LINK, link)
            putExtra(EXTRA_TARGET, target)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        return PendingIntent.getActivity(
            context,
            if (target == TARGET_ACTION) REQUEST_ACTION else REQUEST_WIDGET,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    /** The widget's size in dp, portrait (min width × max height). */
    private fun sizeOf(options: Bundle?): Pair<Int, Int> {
        val width = options?.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH) ?: 0
        val height = options?.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT) ?: 0
        return Pair(
            if (width > 0) width else DEFAULT_WIDTH_DP,
            if (height > 0) height else DEFAULT_HEIGHT_DP,
        )
    }

    /** Pixel size for [dp], scaled down so the longest side fits [MAX_BITMAP_PX]. */
    private fun bitmapSize(dp: Pair<Int, Int>): Pair<Int, Int> {
        val w = dp.first * density
        val h = dp.second * density
        val scale = min(1f, MAX_BITMAP_PX / max(w, h))
        return Pair(max(1, (w * scale).roundToInt()), max(1, (h * scale).roundToInt()))
    }

    private fun background(dp: Pair<Int, Int>, style: StyleSpec, image: String?, rtl: Boolean): Bitmap {
        val (w, h) = bitmapSize(dp)
        val scale = w / (dp.first * density)
        val layer = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(layer)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)

        paint.shader = LinearGradient(
            0f, 0f, w.toFloat(), h.toFloat(),
            style.background, style.backgroundEnd ?: style.background, Shader.TileMode.CLAMP,
        )
        canvas.drawRect(0f, 0f, w.toFloat(), h.toFloat(), paint)
        paint.shader = null

        val photo = image?.let { decode(it, w, h) }
        if (photo != null) {
            val fill = max(w.toFloat() / photo.width, h.toFloat() / photo.height)
            val pw = photo.width * fill
            val ph = photo.height * fill
            canvas.drawBitmap(photo, null, RectF((w - pw) / 2, (h - ph) / 2, (w + pw) / 2, (h + ph) / 2), paint)
            photo.recycle()

            if (style.imageScrim) {
                // The text side fades into the background color; a gradient's
                // direction doesn't follow the layout direction, so flip it.
                val (from, to) = if (rtl) Pair(w.toFloat(), 0f) else Pair(0f, w.toFloat())
                paint.shader = LinearGradient(
                    from, 0f, to, 0f,
                    intArrayOf(alpha(style.background, 0.95f), alpha(style.background, 0.7f), alpha(style.background, 0.1f)),
                    floatArrayOf(0f, 0.5f, 1f),
                    Shader.TileMode.CLAMP,
                )
                canvas.drawRect(0f, 0f, w.toFloat(), h.toFloat(), paint)
                paint.shader = LinearGradient(
                    0f, h.toFloat(), 0f, h / 2f,
                    alpha(style.background, 0.6f), Color.TRANSPARENT, Shader.TileMode.CLAMP,
                )
                canvas.drawRect(0f, 0f, w.toFloat(), h.toFloat(), paint)
                paint.shader = null
            }
        }

        // Round the corners with a shader, which (unlike clipPath) is anti-aliased.
        val output = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val radius = context.resources.getDimension(R.dimen.ltw_corner_radius) * scale
        paint.shader = BitmapShader(layer, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP)
        Canvas(output).drawRoundRect(RectF(0f, 0f, w.toFloat(), h.toFloat()), radius, radius, paint)
        layer.recycle()
        return output
    }

    private fun progressBar(dp: Pair<Int, Int>, progress: Double, accent: Int, track: Int, rtl: Boolean): Bitmap {
        val padding = context.resources.getDimension(R.dimen.ltw_padding) / density
        val (w, h) = bitmapSize(Pair(max(1, (dp.first - 2 * padding).roundToInt()), PROGRESS_HEIGHT_DP))
        val bitmap = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        val radius = h / 2f
        paint.color = track
        canvas.drawRoundRect(RectF(0f, 0f, w.toFloat(), h.toFloat()), radius, radius, paint)
        if (progress > 0) {
            val filled = max(h.toFloat(), (w * progress).toFloat())
            paint.color = accent
            val rect = if (rtl) RectF(w - filled, 0f, w.toFloat(), h.toFloat()) else RectF(0f, 0f, filled, h.toFloat())
            canvas.drawRoundRect(rect, radius, radius, paint)
        }
        return bitmap
    }

    /** Decodes a stored image, subsampled to roughly [w]×[h]. */
    private fun decode(name: String, w: Int, h: Int): Bitmap? {
        val file = LiveTimerStore.image(context, name)
        if (!file.exists()) return null
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(file.path, bounds)
        var sample = 1
        while (bounds.outWidth / (sample * 2) >= w && bounds.outHeight / (sample * 2) >= h) sample *= 2
        return BitmapFactory.decodeFile(file.path, BitmapFactory.Options().apply { inSampleSize = sample })
    }

    private fun alpha(color: Int, alpha: Float): Int =
        Color.argb((Color.alpha(color) * alpha).roundToInt(), Color.red(color), Color.green(color), Color.blue(color))

    companion object {
        const val ACTION_TAP = "io.github.abdoshamss.live_timer_widget.TAP"
        const val EXTRA_LINK = "live_timer_widget.link"
        const val EXTRA_TARGET = "live_timer_widget.target"
        const val TARGET_WIDGET = "widget"
        const val TARGET_ACTION = "action"

        private const val REQUEST_WIDGET = 7_310
        private const val REQUEST_ACTION = 7_311
        private const val COMPACT_WIDTH_DP = 200
        private const val DEFAULT_WIDTH_DP = 250
        private const val DEFAULT_HEIGHT_DP = 110
        private const val PROGRESS_HEIGHT_DP = 6
        private const val MAX_BITMAP_PX = 900f
        private const val TIMER_SP = 34f
        private const val TIMER_SP_COMPACT = 26f
        private const val IDLE_TITLE_SP = 20f
        private const val IDLE_TITLE_SP_COMPACT = 16f
    }
}
