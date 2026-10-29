package io.github.abdoshamss.live_timer_widget

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.util.Log

/**
 * The home-screen widget. Declared by the plugin's manifest, so an app gets
 * it just by depending on the plugin.
 *
 * The clock ticks on its own; what can't (progress, stage, completion) is
 * redrawn by a non-wakeup alarm at the next instant it changes. Non-wakeup
 * alarms only fire while the device is awake, so a running timer costs no
 * battery with the screen off.
 */
class LiveTimerWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        update(context, manager, ids)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        manager: AppWidgetManager,
        id: Int,
        newOptions: Bundle,
    ) {
        // Resized: the bitmaps and the compact layout depend on the size.
        update(context, manager, intArrayOf(id))
    }

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            // The clock is anchored to wall time; re-anchor it.
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED,
            Intent.ACTION_LOCALE_CHANGED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            ACTION_REFRESH -> updateAll(context)
            else -> super.onReceive(context, intent)
        }
    }

    override fun onDisabled(context: Context) {
        schedule(context, null)
    }

    companion object {
        private const val TAG = "LiveTimerWidget"
        private const val ACTION_REFRESH = "io.github.abdoshamss.live_timer_widget.REFRESH"
        private const val REQUEST_REFRESH = 7_312
        private const val MIN_REFRESH_MS = 60_000L
        private const val MAX_REFRESH_MS = 15 * 60_000L

        fun componentName(context: Context) = ComponentName(context, LiveTimerWidgetProvider::class.java)

        fun installedIds(context: Context): IntArray =
            AppWidgetManager.getInstance(context).getAppWidgetIds(componentName(context))

        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            update(context, manager, manager.getAppWidgetIds(componentName(context)))
        }

        private fun update(context: Context, manager: AppWidgetManager, ids: IntArray) {
            val state = LiveTimerStore.state(context)
            val now = System.currentTimeMillis()
            val snapshot = Snapshot.resolve(state.timer, now)
            val renderer = LiveTimerRenderer(context)
            for (id in ids) {
                try {
                    manager.updateAppWidget(id, renderer.render(state, snapshot, manager.getAppWidgetOptions(id)))
                } catch (e: Exception) {
                    // One bad draw (e.g. a bitmap over the launcher's limit)
                    // must not crash the app that triggered it.
                    Log.e(TAG, "Could not draw widget $id", e)
                }
            }
            schedule(context, if (ids.isEmpty() || snapshot.phase == Phase.IDLE) null else nextRefresh(state.timer!!, snapshot, now))
        }

        /**
         * The next phase or stage change, or sooner when the progress (bar
         * and `{percent}`) has moved by about half a percent.
         */
        private fun nextRefresh(timer: TimerSpec, snapshot: Snapshot, now: Long): Long? {
            val change = Snapshot.nextChange(timer, now)
            val goal = timer.goalMs
            val progressMoves = snapshot.phase == Phase.RUNNING && goal != null && goal > 0
            val tick = if (progressMoves) now + (goal!! / 200).coerceIn(MIN_REFRESH_MS, MAX_REFRESH_MS) else null
            return listOfNotNull(change, tick).minOrNull()
        }

        private fun schedule(context: Context, at: Long?) {
            val alarm = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val intent = Intent(context, LiveTimerWidgetProvider::class.java).setAction(ACTION_REFRESH)
            val pending = PendingIntent.getBroadcast(
                context,
                REQUEST_REFRESH,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            if (at == null) alarm.cancel(pending) else alarm.set(AlarmManager.RTC, at, pending)
        }
    }
}
