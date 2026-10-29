package io.github.abdoshamss.live_timer_widget

import android.content.Context
import java.io.File

/** What the Dart side writes and the widget reads: one JSON state + images. */
internal object LiveTimerStore {
    private const val PREFS = "live_timer_widget"
    private const val KEY_STATE = "state"
    private const val IMAGES_DIR = "live_timer_widget"

    fun load(context: Context): String? =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY_STATE, null)

    fun state(context: Context): WidgetState = WidgetState.parse(load(context))

    fun save(context: Context, state: String) {
        // commit, not apply: the widget is redrawn right after and reads it.
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putString(KEY_STATE, state).commit()
    }

    fun image(context: Context, name: String): File = File(imagesDir(context), File(name).name)

    fun saveImage(context: Context, name: String, bytes: ByteArray) {
        val target = image(context, name)
        val temp = File(target.parentFile, "${target.name}.tmp")
        temp.writeBytes(bytes)
        if (!temp.renameTo(target)) {
            temp.delete()
            throw IllegalStateException("Could not store $name")
        }
    }

    fun pruneImages(context: Context, keep: Set<String>) {
        imagesDir(context).listFiles()?.forEach { if (it.name !in keep) it.delete() }
    }

    private fun imagesDir(context: Context): File =
        File(context.filesDir, IMAGES_DIR).apply { mkdirs() }
}
