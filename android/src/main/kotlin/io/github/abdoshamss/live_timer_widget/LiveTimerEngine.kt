package io.github.abdoshamss.live_timer_widget

import org.json.JSONArray
import org.json.JSONObject
import kotlin.math.floor

/**
 * The stored state and the timer rules. Mirrors `lib/src/snapshot.dart`
 * (the reference, pinned by its tests) and the iOS template — keep the three
 * in sync.
 */
internal data class TimerStage(
    val afterMs: Long?,
    val progress: Double?,
    val title: String?,
    val subtitle: String?,
    val image: String?,
    val accent: Int?,
)

internal data class TimerSpec(
    val startMs: Long,
    val endMs: Long?,
    val countDown: Boolean,
    val completion: String,
    val maxMs: Long?,
    val title: String,
    val subtitle: String?,
    val completedTitle: String?,
    val completedSubtitle: String?,
    val image: String?,
    val accent: Int?,
    val showProgress: Boolean,
    val link: String?,
    val stages: List<TimerStage>,
) {
    val goalMs: Long? get() = endMs?.minus(startMs)

    /** How long after the start [stage] is reached; null if never. */
    fun offsetOf(stage: TimerStage): Long? {
        stage.afterMs?.let { return it }
        val progress = stage.progress ?: return null
        if (progress == 0.0) return 0
        val goal = goalMs?.takeIf { it > 0 } ?: return null
        return Math.round(goal * progress)
    }
}

internal data class IdleSpec(
    val title: String,
    val subtitle: String?,
    val actionLabel: String?,
    val image: String?,
    val link: String?,
    val actionLink: String?,
)

internal data class StyleSpec(
    val background: Int = 0xFF1B1530.toInt(),
    val backgroundEnd: Int? = null,
    val foreground: Int = 0xFFFFFFFF.toInt(),
    val muted: Int = 0xCCFFFFFF.toInt(),
    val accent: Int = 0xFF8AC443.toInt(),
    val onAccent: Int = 0xFF14101F.toInt(),
    val track: Int = 0x38FFFFFF,
    val imageScrim: Boolean = true,
)

internal data class WidgetState(
    val rtl: Boolean?,
    val style: StyleSpec,
    val idle: IdleSpec?,
    val timer: TimerSpec?,
) {
    companion object {
        val EMPTY = WidgetState(null, StyleSpec(), null, null)

        fun parse(raw: String?): WidgetState {
            if (raw.isNullOrEmpty()) return EMPTY
            return try {
                val json = JSONObject(raw)
                WidgetState(
                    rtl = json.bool("rtl"),
                    style = json.optJSONObject("style")?.let(::parseStyle) ?: StyleSpec(),
                    idle = json.optJSONObject("idle")?.let(::parseIdle),
                    timer = json.optJSONObject("timer")?.let(::parseTimer),
                )
            } catch (e: Exception) {
                EMPTY
            }
        }

        private fun parseStyle(json: JSONObject): StyleSpec {
            val defaults = StyleSpec()
            return StyleSpec(
                background = json.int("background") ?: defaults.background,
                backgroundEnd = json.int("backgroundEnd"),
                foreground = json.int("foreground") ?: defaults.foreground,
                muted = json.int("muted") ?: defaults.muted,
                accent = json.int("accent") ?: defaults.accent,
                onAccent = json.int("onAccent") ?: defaults.onAccent,
                track = json.int("track") ?: defaults.track,
                imageScrim = json.bool("imageScrim") ?: true,
            )
        }

        private fun parseIdle(json: JSONObject) = IdleSpec(
            title = json.str("title") ?: "",
            subtitle = json.str("subtitle"),
            actionLabel = json.str("actionLabel"),
            image = json.str("image"),
            link = json.str("link"),
            actionLink = json.str("actionLink"),
        )

        private fun parseTimer(json: JSONObject): TimerSpec? {
            val start = json.long("startMs") ?: return null
            val stages = json.optJSONArray("stages") ?: JSONArray()
            return TimerSpec(
                startMs = start,
                endMs = json.long("endMs"),
                countDown = json.str("direction") == "down",
                completion = json.str("completion") ?: "keepCounting",
                maxMs = json.long("maxMs"),
                title = json.str("title") ?: "",
                subtitle = json.str("subtitle"),
                completedTitle = json.str("completedTitle"),
                completedSubtitle = json.str("completedSubtitle"),
                image = json.str("image"),
                accent = json.int("accent"),
                showProgress = json.bool("showProgress") ?: true,
                link = json.str("link"),
                stages = (0 until stages.length()).mapNotNull { i ->
                    stages.optJSONObject(i)?.let {
                        TimerStage(
                            afterMs = it.long("afterMs"),
                            progress = if (it.isNull("progress")) null else it.optDouble("progress"),
                            title = it.str("title"),
                            subtitle = it.str("subtitle"),
                            image = it.str("image"),
                            accent = it.int("accent"),
                        )
                    }
                },
            )
        }

        // `opt*` coerces an explicit JSON null to "null" / 0, hence these.
        private fun JSONObject.str(key: String): String? = if (isNull(key)) null else optString(key)
        private fun JSONObject.long(key: String): Long? = if (isNull(key)) null else optLong(key)
        private fun JSONObject.int(key: String): Int? = if (isNull(key)) null else optLong(key).toInt()
        private fun JSONObject.bool(key: String): Boolean? = if (isNull(key)) null else optBoolean(key)
    }
}

internal enum class Phase { IDLE, RUNNING, COMPLETED }

internal data class Snapshot(
    val phase: Phase,
    val progress: Double? = null,
    val stage: TimerStage? = null,
    val clockMs: Long = 0,
    val ticking: Boolean = false,
    val countingDown: Boolean = false,
    val title: String = "",
    val subtitle: String? = null,
) {
    companion object {
        private val IDLE = Snapshot(Phase.IDLE)

        fun resolve(timer: TimerSpec?, nowMs: Long): Snapshot {
            timer ?: return IDLE
            val elapsed = nowMs - timer.startMs
            if (timer.maxMs != null && elapsed >= timer.maxMs) return IDLE

            val end = timer.endMs
            val completed = end != null && nowMs >= end
            if (completed && timer.completion == "idle") return IDLE

            val goal = timer.goalMs
            val progress = goal?.let {
                if (it <= 0) 1.0 else (elapsed.toDouble() / it).coerceIn(0.0, 1.0)
            }

            val stage = stageAt(timer, elapsed)
            val percent = progress?.let { "${floor(it * 100).toInt()}%" } ?: ""
            fun fill(text: String) = text.replace("{percent}", percent)

            val title = (if (completed) timer.completedTitle else null)
                ?: stage?.title ?: timer.title
            val subtitle = (if (completed) timer.completedSubtitle else null)
                ?: stage?.subtitle ?: timer.subtitle

            var ticking = true
            var countingDown = false
            val clock = when {
                !completed -> {
                    countingDown = timer.countDown
                    if (countingDown) end!! - nowMs else elapsed
                }
                timer.completion == "freeze" -> {
                    ticking = false
                    if (timer.countDown) 0 else goal!!
                }
                // keepCounting: a countdown becomes overtime since the end.
                else -> if (timer.countDown) nowMs - end!! else elapsed
            }

            return Snapshot(
                phase = if (completed) Phase.COMPLETED else Phase.RUNNING,
                progress = progress,
                stage = stage,
                clockMs = clock.coerceAtLeast(0),
                ticking = ticking,
                countingDown = countingDown,
                title = fill(title),
                subtitle = subtitle?.let(::fill),
            )
        }

        /** The next instant after [nowMs] at which [resolve] changes phase or stage. */
        fun nextChange(timer: TimerSpec, nowMs: Long): Long? {
            val candidates = mutableListOf<Long>()
            timer.endMs?.let(candidates::add)
            timer.maxMs?.let { candidates.add(timer.startMs + it) }
            timer.stages.forEach { stage ->
                timer.offsetOf(stage)?.let { candidates.add(timer.startMs + it) }
            }
            return candidates.filter { it > nowMs }.minOrNull()
        }

        private fun stageAt(timer: TimerSpec, elapsed: Long): TimerStage? {
            var match: TimerStage? = null
            var best: Long? = null
            for (stage in timer.stages) {
                val offset = timer.offsetOf(stage) ?: continue
                if (offset > elapsed) continue
                // Later in the list wins a tie.
                if (best == null || offset >= best) {
                    best = offset
                    match = stage
                }
            }
            return match
        }
    }
}
