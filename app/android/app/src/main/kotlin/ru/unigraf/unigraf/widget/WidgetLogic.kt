package ru.unigraf.unigraf.widget

import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone

/**
 * Чистая логика виджетов — без Android-классов, поэтому проверяется обычными тестами.
 *
 * Данные приходят из приложения как «снимок» расписания на 7 дней (АРХИТЕКТУРА.md, §7.6).
 * Виджет сам смотрит на часы и выбирает из снимка текущую или следующую пару,
 * поэтому остаётся верным целую неделю, даже если приложение не запускали.
 */
/** Цвета предмета (ARGB): насыщенный, мягкий фон и цвет текста на нём. */
data class WidgetTone(val accent: Int, val container: Int, val onContainer: Int)

/** Цвета предмета для светлой и тёмной темы; виджет берёт подходящие по режиму телефона. */
data class WidgetToneSet(val light: WidgetTone, val dark: WidgetTone) {
    fun pick(night: Boolean): WidgetTone = if (night) dark else light
}

data class WidgetLesson(
    val startMs: Long,
    val endMs: Long,
    val pair: Int,
    val short: String,
    val subject: String,
    val room: String?,
    val teacher: String?,
    val kind: String,
    val hasHomework: Boolean,
    /** Пара изменена вами или старостой. */
    val changed: Boolean = false,
    /** Цвета предмета из приложения (null — виджет красит сам). */
    val tone: WidgetToneSet? = null,
) {
    /** Л / П / Ф / К / А / З / Э — значок типа занятия (А — аттестация, З — зачёт, Э — экзамен). */
    val kindLetter: String
        get() = when (kind) {
            "lecture" -> "Л"
            "practice" -> "П"
            "pe" -> "Ф"
            "curator" -> "К"
            "attestation" -> "А"
            "credit" -> "З"
            "exam" -> "Э"
            else -> ""
        }
}

data class WidgetDay(val date: String, val lessons: List<WidgetLesson>)

/** Цвета виджета (ARGB). Приложение присылает их по выбранной цветовой теме; если не прислало — виджет берёт цвета из ресурсов. */
data class WidgetColors(
    val bg: Int,
    val text: Int,
    val textSecondary: Int,
    val accent: Int,
    val highlight: Int,
    val badgeBg: Int,
    val badgeText: Int,
)

/** Одно невыполненное домашнее задание для виджета «Домашка». */
data class HomeworkEntry(val subject: String, val short: String, val text: String, val due: String, val files: Int, val tone: WidgetToneSet? = null)

data class WidgetSnapshot(
    val weekLabel: String,
    val days: List<WidgetDay>,
    val homeworkCount: Int = 0,
    val homework: List<HomeworkEntry> = emptyList(),
    val lightColors: WidgetColors? = null,
    val darkColors: WidgetColors? = null,
) {
    val allLessons: List<WidgetLesson> get() = days.flatMap { it.lessons }
}

/** Строка виджета «Неделя»: день, сколько пар и во сколько начало/конец. */
data class WeekRow(val date: String, val dayLabel: String, val count: Int, val range: String, val isToday: Boolean)

object WidgetLogic {
    private const val MOSCOW_OFFSET_MS = 3 * 3600_000L

    /** «2026-10-08T09:00+03:00» → миллисекунды (UTC). */
    fun parseMoment(text: String): Long {
        val format = SimpleDateFormat("yyyy-MM-dd'T'HH:mmXXX", Locale.US)
        format.timeZone = TimeZone.getTimeZone("UTC")
        return format.parse(text)!!.time
    }

    fun parse(json: String): WidgetSnapshot {
        val root = JSONObject(json)
        val daysJson = root.getJSONArray("days")
        val days = (0 until daysJson.length()).map { i ->
            val day = daysJson.getJSONObject(i)
            val lessonsJson = day.getJSONArray("lessons")
            WidgetDay(
                date = day.getString("date"),
                lessons = (0 until lessonsJson.length()).map { j ->
                    val l = lessonsJson.getJSONObject(j)
                    WidgetLesson(
                        startMs = parseMoment(l.getString("start")),
                        endMs = parseMoment(l.getString("end")),
                        pair = l.getInt("pair"),
                        short = l.getString("short"),
                        subject = l.getString("subject"),
                        room = if (l.isNull("room")) null else l.getString("room"),
                        teacher = if (l.isNull("teacher")) null else l.getString("teacher"),
                        kind = l.getString("kind"),
                        hasHomework = l.optBoolean("hasHomework", false),
                        changed = l.optBoolean("changed", false),
                        tone = parseToneSet(l.optJSONObject("tone")),
                    )
                },
            )
        }
        return WidgetSnapshot(
            weekLabel = root.optString("weekLabel", ""),
            days = days,
            homeworkCount = root.optInt("homeworkCount", 0),
            homework = parseHomework(root),
            lightColors = parseColors(root.optJSONObject("colors")?.optJSONObject("light")),
            darkColors = parseColors(root.optJSONObject("colors")?.optJSONObject("dark")),
        )
    }

    private fun parseHomework(root: JSONObject): List<HomeworkEntry> {
        val array = root.optJSONArray("homework") ?: return emptyList()
        return (0 until array.length()).map { i ->
            val h = array.getJSONObject(i)
            HomeworkEntry(
                subject = h.getString("subject"),
                short = h.optString("short", h.getString("subject")),
                text = h.optString("text", ""),
                due = h.getString("due"),
                files = h.optInt("files", 0),
                tone = parseToneSet(h.optJSONObject("tone")),
            )
        }
    }

    /** «#RRGGBB» → ARGB. Без android.graphics.Color, чтобы проверять обычными тестами. */
    fun parseHex(hex: String): Int = ("FF" + hex.removePrefix("#")).toLong(16).toInt()

    private fun parseTone(json: JSONObject?): WidgetTone? {
        if (json == null) return null
        return try {
            WidgetTone(parseHex(json.getString("accent")), parseHex(json.getString("container")), parseHex(json.getString("onContainer")))
        } catch (e: Exception) {
            null
        }
    }

    private fun parseToneSet(json: JSONObject?): WidgetToneSet? {
        val light = parseTone(json?.optJSONObject("light")) ?: return null
        val dark = parseTone(json?.optJSONObject("dark")) ?: return null
        return WidgetToneSet(light, dark)
    }

    private fun parseColors(json: JSONObject?): WidgetColors? {
        if (json == null) return null
        return try {
            WidgetColors(
                bg = parseHex(json.getString("bg")),
                text = parseHex(json.getString("text")),
                textSecondary = parseHex(json.getString("textSecondary")),
                accent = parseHex(json.getString("accent")),
                highlight = parseHex(json.getString("highlight")),
                badgeBg = parseHex(json.getString("badgeBg")),
                badgeText = parseHex(json.getString("badgeText")),
            )
        } catch (e: Exception) {
            null // повреждённые цвета — просто стандартное оформление
        }
    }

    /** Пара, которая идёт прямо сейчас. */
    fun current(snapshot: WidgetSnapshot, nowMs: Long): WidgetLesson? =
        snapshot.allLessons.firstOrNull { nowMs >= it.startMs && nowMs < it.endMs }

    /** Ближайшая будущая пара (на любой день снимка). */
    fun next(snapshot: WidgetSnapshot, nowMs: Long): WidgetLesson? =
        snapshot.allLessons.filter { it.startMs > nowMs }.minByOrNull { it.startMs }

    /** Что показать в виджете 2×2: идущая пара или, если не идёт, следующая. */
    data class NowNext(val lesson: WidgetLesson?, val isCurrent: Boolean)

    fun nowNext(snapshot: WidgetSnapshot, nowMs: Long): NowNext {
        current(snapshot, nowMs)?.let { return NowNext(it, true) }
        return NowNext(next(snapshot, nowMs), false)
    }

    /** Дата «сегодня» по Москве в формате ГГГГ-ММ-ДД. */
    fun moscowDate(nowMs: Long): String {
        val format = SimpleDateFormat("yyyy-MM-dd", Locale.US)
        format.timeZone = TimeZone.getTimeZone("UTC")
        return format.format(nowMs + MOSCOW_OFFSET_MS)
    }

    /**
     * Что показать в виджете 4×2: пары сегодняшнего дня; когда они закончились (или их нет) —
     * пары ближайшего следующего дня с парами и пометка «Завтра» / название дня.
     */
    data class TodayView(val date: String, val lessons: List<WidgetLesson>, val isToday: Boolean)

    fun todayView(snapshot: WidgetSnapshot, nowMs: Long): TodayView {
        val today = moscowDate(nowMs)
        val todays = snapshot.days.firstOrNull { it.date == today }?.lessons.orEmpty()
        if (todays.isNotEmpty() && todays.any { it.endMs > nowMs }) return TodayView(today, todays, true)

        val later = snapshot.days.filter { it.date > today && it.lessons.isNotEmpty() }.minByOrNull { it.date }
        return if (later != null) TodayView(later.date, later.lessons, false) else TodayView(today, todays, true)
    }

    /** Ближайший момент, когда виджет нужно перерисовать: начало или конец какой-то пары. */
    fun nextBoundary(snapshot: WidgetSnapshot, nowMs: Long): Long? =
        snapshot.allLessons.flatMap { listOf(it.startMs, it.endMs) }.filter { it > nowMs }.minOrNull()

    /** «через 12 мин» для подписи, когда обратный отсчёт не нужен. */
    fun minutesText(ms: Long): String {
        val minutes = (ms / 60_000).coerceAtLeast(0)
        return if (minutes >= 60) "${minutes / 60} ч ${minutes % 60} мин" else "$minutes мин"
    }

    fun weekdayName(date: String): String {
        val format = SimpleDateFormat("yyyy-MM-dd", Locale.US)
        format.timeZone = TimeZone.getTimeZone("UTC")
        val cal = java.util.Calendar.getInstance(TimeZone.getTimeZone("UTC"))
        cal.time = format.parse(date)!!
        return when (cal.get(java.util.Calendar.DAY_OF_WEEK)) {
            java.util.Calendar.MONDAY -> "Понедельник"
            java.util.Calendar.TUESDAY -> "Вторник"
            java.util.Calendar.WEDNESDAY -> "Среда"
            java.util.Calendar.THURSDAY -> "Четверг"
            java.util.Calendar.FRIDAY -> "Пятница"
            java.util.Calendar.SATURDAY -> "Суббота"
            else -> "Воскресенье"
        }
    }

    /** Время по Москве «09:00» из момента. */
    fun timeText(ms: Long): String {
        val format = SimpleDateFormat("HH:mm", Locale.US)
        format.timeZone = TimeZone.getTimeZone("GMT+03:00")
        return format.format(ms)
    }

    fun weekdayShort(date: String): String = when (weekdayName(date)) {
        "Понедельник" -> "Пн"
        "Вторник" -> "Вт"
        "Среда" -> "Ср"
        "Четверг" -> "Чт"
        "Пятница" -> "Пт"
        "Суббота" -> "Сб"
        else -> "Вс"
    }

    /** «7» из «2026-10-07». */
    fun dayNumber(date: String): String = date.substring(8).trimStart('0')

    /** Завтрашний день снимка: пары завтрашнего дня (пустой список, если их нет). */
    fun tomorrowView(snapshot: WidgetSnapshot, nowMs: Long): TodayView {
        val tomorrow = moscowDate(nowMs + 24 * 3600_000L)
        return TodayView(tomorrow, snapshot.days.firstOrNull { it.date == tomorrow }?.lessons.orEmpty(), false)
    }

    /** Строки виджета «Неделя» — все дни снимка. */
    fun weekRows(snapshot: WidgetSnapshot, nowMs: Long): List<WeekRow> {
        val today = moscowDate(nowMs)
        return snapshot.days.map { day ->
            val first = day.lessons.firstOrNull()
            val last = day.lessons.lastOrNull()
            WeekRow(
                date = day.date,
                dayLabel = weekdayShort(day.date) + " " + dayNumber(day.date),
                count = day.lessons.size,
                range = if (first == null || last == null) "" else timeText(first.startMs) + "–" + timeText(last.endMs),
                isToday = day.date == today,
            )
        }
    }

    /** «1 пара», «2 пары», «5 пар». */
    fun pairsText(count: Int): String {
        val mod10 = count % 10
        val mod100 = count % 100
        val word = if (mod100 in 11..14) "пар" else when (mod10) {
            1 -> "пара"
            2, 3, 4 -> "пары"
            else -> "пар"
        }
        return "$count $word"
    }

    /** «1 задание», «2 задания», «5 заданий». */
    fun tasksText(count: Int): String {
        val mod10 = count % 10
        val mod100 = count % 100
        val word = if (mod100 in 11..14) "заданий" else when (mod10) {
            1 -> "задание"
            2, 3, 4 -> "задания"
            else -> "заданий"
        }
        return "$count $word"
    }

    /** Срок ДЗ человеческими словами: «сегодня», «завтра», «Пт 9», «просрочено». */
    fun dueLabel(due: String, today: String): String {
        val tomorrow = moscowDateFrom(today, 1)
        return when {
            due < today -> "просрочено"
            due == today -> "сегодня"
            due == tomorrow -> "завтра"
            else -> weekdayShort(due) + " " + dayNumber(due)
        }
    }

    private fun moscowDateFrom(date: String, plusDays: Int): String {
        val format = SimpleDateFormat("yyyy-MM-dd", Locale.US)
        format.timeZone = TimeZone.getTimeZone("UTC")
        return format.format(format.parse(date)!!.time + plusDays * 24 * 3600_000L)
    }
}
