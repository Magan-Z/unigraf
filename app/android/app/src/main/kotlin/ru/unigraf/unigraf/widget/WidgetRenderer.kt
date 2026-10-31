package ru.unigraf.unigraf.widget

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.res.ColorStateList
import android.content.res.Configuration
import android.net.Uri
import android.os.Build
import android.os.SystemClock
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.style.StyleSpan
import android.graphics.Typeface
import android.util.TypedValue
import android.view.View
import android.widget.RemoteViews
import ru.unigraf.unigraf.MainActivity
import ru.unigraf.unigraf.R
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone

/** Собирает картинку виджетов (RemoteViews) из снимка и текущего времени. */
object WidgetRenderer {
    // Обратный отсчёт показываем, только если до события не больше этого времени
    private const val COUNTDOWN_LIMIT_MS = 3 * 3600_000L

    /** Элементы одной строки виджета «Сегодня»/«Завтра»: время, название, аудитория, точка и линия на оси времени, пометка «изменено». */
    private data class DayRow(val row: Int, val time: Int, val subject: Int, val room: Int, val line: Int, val dot: Int, val changed: Int)

    private val rows = listOf(
        DayRow(R.id.row_1, R.id.time_1, R.id.subject_1, R.id.room_1, R.id.line_1, R.id.dot_1, R.id.chg_1),
        DayRow(R.id.row_2, R.id.time_2, R.id.subject_2, R.id.room_2, R.id.line_2, R.id.dot_2, R.id.chg_2),
        DayRow(R.id.row_3, R.id.time_3, R.id.subject_3, R.id.room_3, R.id.line_3, R.id.dot_3, R.id.chg_3),
        DayRow(R.id.row_4, R.id.time_4, R.id.subject_4, R.id.room_4, R.id.line_4, R.id.dot_4, R.id.chg_4),
        DayRow(R.id.row_5, R.id.time_5, R.id.subject_5, R.id.room_5, R.id.line_5, R.id.dot_5, R.id.chg_5),
    )

    private fun moscowTime(ms: Long): String {
        val format = SimpleDateFormat("HH:mm", Locale.US)
        format.timeZone = TimeZone.getTimeZone("GMT+03:00")
        return format.format(ms)
    }

    private fun openApp(context: Context, request: Int, uri: String? = null): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            if (uri != null) data = Uri.parse(uri)
        }
        return PendingIntent.getActivity(
            context, request, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }


    /**
     * Нажатие на сам виджет открывает меню действий (открыть приложение, добавить ДЗ, завтра, неделя, поиск).
     * Удержание остаётся системным (перемещение и удаление виджета).
     */
    private fun openMenu(context: Context, request: Int): PendingIntent {
        val intent = Intent(context, WidgetMenuActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        return PendingIntent.getActivity(
            context, 100 + request, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    // ---------- цвета выбранной темы ----------

    /** Цвета темы приложения для текущего режима (светлый/тёмный). Только Android 12+: там можно перекрашивать фон. */
    private fun colorsFor(context: Context, snapshot: WidgetSnapshot?): WidgetColors? {
        if (Build.VERSION.SDK_INT < 31 || snapshot == null) return null
        val night = (context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES
        return if (night) snapshot.darkColors else snapshot.lightColors
    }

    private fun isNight(context: Context): Boolean =
        (context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES

    /** Цвета предмета для текущего режима (null — приложение не прислало или Android старше 12: виджет остаётся в стандартных цветах). */
    private fun toneOf(context: Context, tone: WidgetToneSet?): WidgetTone? = if (Build.VERSION.SDK_INT >= 31) tone?.pick(isNight(context)) else null

    private fun tint(views: RemoteViews, id: Int, color: Int) {
        if (Build.VERSION.SDK_INT >= 31) views.setColorStateList(id, "setBackgroundTintList", ColorStateList.valueOf(color))
    }

    /**
     * Красит виджет в цвета темы. [text] — основной текст, [secondary] — второстепенный, [accent] — акцент,
     * [badges] — «таблетки» на янтарном фоне, [plates] — таблички с аудиторией.
     */
    private fun paint(
        views: RemoteViews,
        c: WidgetColors?,
        text: List<Int> = emptyList(),
        secondary: List<Int> = emptyList(),
        accent: List<Int> = emptyList(),
        badges: List<Int> = emptyList(),
        plates: List<Int> = emptyList(),
    ) {
        if (c == null) return
        tint(views, R.id.widget_root, c.bg)
        text.forEach { views.setTextColor(it, c.text) }
        secondary.forEach { views.setTextColor(it, c.textSecondary) }
        accent.forEach { views.setTextColor(it, c.accent) }
        badges.forEach { tint(views, it, c.badgeBg); views.setTextColor(it, c.badgeText) }
        plates.forEach { tint(views, it, c.highlight) }
    }

    /** Цвет «пустых» элементов (линия времени, незакрашенные точки): второстепенный текст, но бледный. */
    private fun railColor(c: WidgetColors): Int = (c.textSecondary and 0x00FFFFFF) or (0x44 shl 24)

    /** Табличка с аудиторией: насыщенный цвет предмета (или акцент темы) и текст цвета фона виджета. */
    private fun paintPlate(views: RemoteViews, id: Int, tone: WidgetTone?, c: WidgetColors?) {
        val fill = tone?.accent ?: c?.accent ?: return
        tint(views, id, fill)
        if (c != null) views.setTextColor(id, c.bg)
    }

    /**
     * Размер надписи на табличке: номер вроде «2-05» крупный, а длинное место («3 корпус», «спортзал», «читальный зал»)
     * мельче и при необходимости в две строки, чтобы табличка не отнимала место у названия предмета.
     */
    private fun fitPlateText(views: RemoteViews, id: Int, room: String) {
        val (size, lines) = when {
            room.length <= 6 -> 22f to 1
            room.length <= 10 -> 13f to 1
            else -> 12f to 2
        }
        views.setTextViewTextSize(id, TypedValue.COMPLEX_UNIT_SP, size)
        views.setInt(id, "setMaxLines", lines)
    }

    /** Маленькая плашка аудитории в строке: мягкий фон цвета предмета и текст на нём. */
    private fun paintPill(views: RemoteViews, id: Int, tone: WidgetTone?, c: WidgetColors?) {
        if (tone != null) {
            tint(views, id, tone.container)
            views.setTextColor(id, tone.onContainer)
        } else if (c != null) {
            tint(views, id, c.highlight)
            views.setTextColor(id, c.text)
        }
    }

    /** Подпись «Идёт сейчас» — янтарная плашка, «Дальше» — спокойная плашка цвета темы. */
    private fun paintStatusLabel(views: RemoteViews, id: Int, isCurrent: Boolean, c: WidgetColors?) {
        if (c == null) return
        if (isCurrent) {
            tint(views, id, c.badgeBg)
            views.setTextColor(id, c.badgeText)
        } else {
            tint(views, id, c.highlight)
            views.setTextColor(id, c.accent)
        }
    }

    /** Подсветка строки (идущая пара, сегодняшний день): фон и, если есть тема, её цвет. */
    private fun highlightRow(views: RemoteViews, row: Int, on: Boolean, c: WidgetColors?) {
        views.setInt(row, "setBackgroundResource", if (on) R.drawable.widget_row_highlight else 0)
        if (on && c != null) tint(views, row, c.highlight)
    }

    /** Обратный отсчёт («до конца 42 мин») или, если событие далеко, подпись «Четверг, 09:00». */
    private fun countdown(
        views: RemoteViews, countdownId: Int, statusId: Int,
        snapshot: WidgetSnapshot, lesson: WidgetLesson, isCurrent: Boolean, nowMs: Long,
    ) {
        val target = if (isCurrent) lesson.endMs else lesson.startMs
        val remaining = target - nowMs
        if (remaining <= COUNTDOWN_LIMIT_MS) {
            // Chronometer тикает сам, без перерисовки виджета каждую секунду
            views.setViewVisibility(countdownId, View.VISIBLE)
            views.setViewVisibility(statusId, View.GONE)
            views.setChronometerCountDown(countdownId, true)
            views.setChronometer(countdownId, SystemClock.elapsedRealtime() + remaining, if (isCurrent) "до конца %s" else "через %s", true)
        } else {
            views.setViewVisibility(countdownId, View.GONE)
            views.setViewVisibility(statusId, View.VISIBLE)
            val day = WidgetLogic.weekdayName(snapshotDate(snapshot, lesson))
            views.setTextViewText(statusId, "$day, ${moscowTime(lesson.startMs)}")
        }
    }

    // ---------- 2×2: «Сейчас / Далее» ----------

    fun nowNext(context: Context, snapshot: WidgetSnapshot?, nowMs: Long): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_now_next)
        views.setOnClickPendingIntent(R.id.widget_root, openMenu(context, 1))

        val colors = colorsFor(context, snapshot)
        paint(views, colors, text = listOf(R.id.subject), secondary = listOf(R.id.countdown, R.id.status), badges = listOf(R.id.badge))
        val state = snapshot?.let { WidgetLogic.nowNext(it, nowMs) }
        val lesson = state?.lesson
        if (lesson == null) {
            views.setTextViewText(R.id.label, if (snapshot == null) "Откройте приложение" else "Пар нет")
            paintStatusLabel(views, R.id.label, false, colors)
            views.setTextViewText(R.id.subject, "")
            views.setTextViewText(R.id.room, "—")
            paintPlate(views, R.id.room, null, colors)
            views.setViewVisibility(R.id.badge, View.INVISIBLE)
            views.setViewVisibility(R.id.countdown, View.GONE)
            views.setViewVisibility(R.id.status, View.GONE)
            return views
        }

        views.setTextViewText(R.id.label, if (state.isCurrent) "Идёт сейчас" else "Дальше")
        paintStatusLabel(views, R.id.label, state.isCurrent, colors)
        views.setTextViewText(R.id.subject, lesson.short)
        // Обычный номер («2-05») — крупно; длинное место («3 корпус») — та же табличка, но мелким шрифтом в две строки
        val roomText = lesson.room ?: "—"
        val long = roomText.length > 6
        views.setViewVisibility(R.id.room, if (long) View.GONE else View.VISIBLE)
        views.setViewVisibility(R.id.room_long, if (long) View.VISIBLE else View.GONE)
        views.setTextViewText(R.id.room, roomText)
        views.setTextViewText(R.id.room_long, roomText)
        paintPlate(views, R.id.room, toneOf(context, lesson.tone), colors)
        paintPlate(views, R.id.room_long, toneOf(context, lesson.tone), colors)
        views.setTextViewText(R.id.badge, lesson.kindLetter)
        views.setViewVisibility(R.id.badge, if (lesson.kindLetter.isEmpty()) View.INVISIBLE else View.VISIBLE)

        countdown(views, R.id.countdown, R.id.status, snapshot, lesson, state.isCurrent, nowMs)
        return views
    }

    private fun snapshotDate(snapshot: WidgetSnapshot, lesson: WidgetLesson): String =
        snapshot.days.first { day -> day.lessons.contains(lesson) }.date

    // ---------- 4×2: «Сегодня» и «Завтра» ----------

    fun today(context: Context, snapshot: WidgetSnapshot?, nowMs: Long): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_today)
        views.setOnClickPendingIntent(R.id.widget_root, openMenu(context, 2))
        val colors = colorsFor(context, snapshot)
        paintDayHeader(views, colors)

        if (snapshot == null) {
            views.setTextViewText(R.id.title, "Откройте приложение")
            views.setTextViewText(R.id.week, "")
            for (r in rows) views.setViewVisibility(r.row, View.GONE)
            views.setOnClickPendingIntent(R.id.add_homework, openApp(context, 3, "unigraf://homework/new"))
            return views
        }

        val view = WidgetLogic.todayView(snapshot, nowMs)
        val tomorrow = WidgetLogic.moscowDate(nowMs + 24 * 3600_000L)
        views.setTextViewText(
            R.id.title,
            when {
                view.lessons.isEmpty() -> "Пар нет"
                view.isToday -> "Сегодня"
                view.date == tomorrow -> "Завтра"
                else -> WidgetLogic.weekdayName(view.date)
            },
        )
        fillDay(context, views, snapshot, view, nowMs, colors, request = 3)
        return views
    }

    /** «Завтра»: пары завтрашнего дня (в той же вёрстке, что «Сегодня»). */
    fun tomorrow(context: Context, snapshot: WidgetSnapshot?, nowMs: Long): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_today)
        views.setOnClickPendingIntent(R.id.widget_root, openMenu(context, 4))
        val colors = colorsFor(context, snapshot)
        paintDayHeader(views, colors)

        if (snapshot == null) {
            views.setTextViewText(R.id.title, "Откройте приложение")
            views.setTextViewText(R.id.week, "")
            for (r in rows) views.setViewVisibility(r.row, View.GONE)
            views.setOnClickPendingIntent(R.id.add_homework, openApp(context, 5, "unigraf://homework/new"))
            return views
        }
        val view = WidgetLogic.tomorrowView(snapshot, nowMs)
        views.setTextViewText(R.id.title, if (view.lessons.isEmpty()) "Завтра пар нет" else "Завтра, " + WidgetLogic.weekdayShort(view.date).lowercase())
        fillDay(context, views, snapshot, view, nowMs, colors, request = 5)
        return views
    }

    /** Цвета заголовка и постоянных частей строк (время, название); цвета предмета ставятся позже, для каждой пары. */
    private fun paintDayHeader(views: RemoteViews, colors: WidgetColors?) {
        paint(views, colors, text = listOf(R.id.title) + rows.map { it.subject }, secondary = rows.map { it.time }, accent = listOf(R.id.week), badges = listOf(R.id.add_homework))
        if (colors != null) rows.forEach { tint(views, it.line, railColor(colors)) }
    }

    /** Заполняет строки пар дня и кнопку «+ ДЗ» (общая часть «Сегодня» и «Завтра»). */
    private fun fillDay(
        context: Context, views: RemoteViews, snapshot: WidgetSnapshot, view: WidgetLogic.TodayView,
        nowMs: Long, colors: WidgetColors?, request: Int,
    ) {
        views.setTextViewText(R.id.week, snapshot.weekLabel)
        for ((i, r) in rows.withIndex()) {
            val lesson = view.lessons.getOrNull(i)
            if (lesson == null) {
                views.setViewVisibility(r.row, View.GONE)
                continue
            }
            views.setViewVisibility(r.row, View.VISIBLE)
            views.setTextViewText(r.time, moscowTime(lesson.startMs))
            views.setTextViewText(r.subject, lesson.short)
            views.setTextViewText(r.room, lesson.room ?: "")
            views.setViewVisibility(r.room, if (lesson.room == null) View.GONE else View.VISIBLE)
            val tone = toneOf(context, lesson.tone)
            paintPill(views, r.room, tone, colors)
            (tone?.accent ?: colors?.accent)?.let { tint(views, r.dot, it) }
            views.setViewVisibility(r.changed, if (lesson.changed) View.VISIBLE else View.GONE)
            highlightRow(views, r.row, view.isToday && nowMs >= lesson.startMs && nowMs < lesson.endMs, colors)
        }

        // «+ ДЗ» — открывает ввод домашки с предметом ближайшей (или идущей) пары
        val subject = view.lessons.firstOrNull { it.endMs > nowMs }?.subject ?: view.lessons.lastOrNull()?.subject
        val uri = "unigraf://homework/new" + if (subject != null) "?subject=" + Uri.encode(subject) else ""
        views.setOnClickPendingIntent(R.id.add_homework, openApp(context, request, uri))
    }

    // ---------- 4×1: ближайшая пара строкой ----------

    fun strip(context: Context, snapshot: WidgetSnapshot?, nowMs: Long): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_strip)
        views.setOnClickPendingIntent(R.id.widget_root, openMenu(context, 6))
        val colors = colorsFor(context, snapshot)
        paint(views, colors, text = listOf(R.id.subject), secondary = listOf(R.id.teacher, R.id.countdown, R.id.status), accent = listOf(R.id.label))

        val state = snapshot?.let { WidgetLogic.nowNext(it, nowMs) }
        val lesson = state?.lesson
        if (snapshot == null || lesson == null) {
            views.setTextViewText(R.id.label, if (snapshot == null) "Откройте" else "Пар нет")
            views.setTextViewText(R.id.subject, if (snapshot == null) "Откройте приложение" else "Ближайших пар нет")
            views.setTextViewText(R.id.teacher, "")
            views.setViewVisibility(R.id.room, View.GONE)
            views.setViewVisibility(R.id.countdown, View.GONE)
            views.setViewVisibility(R.id.status, View.GONE)
            return views
        }
        views.setViewVisibility(R.id.room, if (lesson.room != null) View.VISIBLE else View.GONE)
        views.setTextViewText(R.id.label, if (state.isCurrent) "Идёт сейчас" else "Дальше")
        views.setTextViewText(R.id.subject, lesson.short)
        views.setTextViewText(R.id.teacher, lesson.teacher ?: "")
        views.setTextViewText(R.id.room, lesson.room ?: "")
        fitPlateText(views, R.id.room, lesson.room ?: "")
        paintPlate(views, R.id.room, toneOf(context, lesson.tone), colors)
        countdown(views, R.id.countdown, R.id.status, snapshot, lesson, state.isCurrent, nowMs)
        return views
    }

    // ---------- 3×1: аудитория крупно ----------

    fun room(context: Context, snapshot: WidgetSnapshot?, nowMs: Long): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_room)
        views.setOnClickPendingIntent(R.id.widget_root, openMenu(context, 7))
        val colors = colorsFor(context, snapshot)
        paint(views, colors, text = listOf(R.id.subject), secondary = listOf(R.id.countdown, R.id.status), accent = listOf(R.id.label))

        val state = snapshot?.let { WidgetLogic.nowNext(it, nowMs) }
        val lesson = state?.lesson
        if (snapshot == null || lesson == null) {
            views.setTextViewText(R.id.room, "—")
            paintPlate(views, R.id.room, null, colors)
            views.setViewVisibility(R.id.label, View.VISIBLE)
            views.setTextViewText(R.id.label, if (snapshot == null) "Откройте" else "Пар нет")
            views.setTextViewText(R.id.subject, if (snapshot == null) "приложение" else "Ближайших пар нет")
            views.setViewVisibility(R.id.countdown, View.GONE)
            views.setViewVisibility(R.id.status, View.GONE)
            return views
        }
        // Обычный номер — крупная табличка во всю высоту; длинное название («3 корпус») — небольшая табличка по размеру текста
        val roomText = lesson.room ?: "—"
        val long = roomText.length > 6
        views.setViewVisibility(R.id.room, if (long) View.GONE else View.VISIBLE)
        views.setViewVisibility(R.id.room_long, if (long) View.VISIBLE else View.GONE)
        views.setTextViewText(R.id.room, roomText)
        views.setTextViewText(R.id.room_long, roomText)
        paintPlate(views, R.id.room, toneOf(context, lesson.tone), colors)
        paintPlate(views, R.id.room_long, toneOf(context, lesson.tone), colors)
        // Подпись «Идёт сейчас/Дальше» здесь не нужна: её говорит сам отсчёт («до конца…» / «через…»), а места мало
        views.setViewVisibility(R.id.label, View.GONE)
        views.setTextViewText(R.id.subject, lesson.short)
        countdown(views, R.id.countdown, R.id.status, snapshot, lesson, state.isCurrent, nowMs)
        return views
    }

    // ---------- 4×4: неделя ----------

    /** Идентификаторы строк берём по имени: так не нужно перечислять десятки одинаковых констант R.id. */
    private lateinit var appContext: Context
    private fun idByName(name: String): Int = appContext.resources.getIdentifier(name, "id", appContext.packageName)

    /** В шкале дня не больше стольких точек (больше пяти пар в день не бывает). */
    private const val METER_DOTS = 5

    fun week(context: Context, snapshot: WidgetSnapshot?, nowMs: Long): RemoteViews {
        appContext = context.applicationContext
        val views = RemoteViews(context.packageName, R.layout.widget_week)
        views.setOnClickPendingIntent(R.id.widget_root, openMenu(context, 8))
        val ids = (1..7).map { Triple(idByName("week_row_$it"), idByName("week_day_$it"), idByName("week_info_$it")) }
        val colors = colorsFor(context, snapshot)
        paint(views, colors, text = listOf(R.id.title) + ids.map { it.second }, secondary = ids.map { it.third }, accent = listOf(R.id.week))

        views.setTextViewText(R.id.title, if (snapshot == null) "Откройте приложение" else "Неделя")
        views.setTextViewText(R.id.week, snapshot?.weekLabel ?: "")
        val data = snapshot?.let { WidgetLogic.weekRows(it, nowMs) }.orEmpty()
        for ((i, rowIds) in ids.withIndex()) {
            val (row, day, info) = rowIds
            val item = data.getOrNull(i)
            if (item == null) {
                views.setViewVisibility(row, View.GONE)
                continue
            }
            views.setViewVisibility(row, View.VISIBLE)
            views.setTextViewText(day, item.dayLabel)
            views.setTextViewText(info, if (item.count == 0) "Пар нет" else WidgetLogic.pairsText(item.count) + " · " + item.range)
            // Шкала: столько закрашенных точек, сколько пар в этот день; остальные бледные (до Android 12 их просто не видно)
            for (j in 1..METER_DOTS) {
                val dot = idByName("week_dot_${i + 1}_$j")
                val filled = j <= item.count
                if (colors != null) {
                    tint(views, dot, if (filled) colors.accent else railColor(colors))
                    views.setViewVisibility(dot, View.VISIBLE)
                } else {
                    views.setViewVisibility(dot, if (filled) View.VISIBLE else View.INVISIBLE)
                }
            }
            highlightRow(views, row, item.isToday, colors)
        }
        return views
    }

    // ---------- «Домашка» ----------

    fun homework(context: Context, snapshot: WidgetSnapshot?, nowMs: Long): RemoteViews {
        appContext = context.applicationContext
        val views = RemoteViews(context.packageName, R.layout.widget_homework)
        views.setOnClickPendingIntent(R.id.widget_root, openMenu(context, 9))
        views.setOnClickPendingIntent(R.id.add_homework, openApp(context, 10, "unigraf://homework/new"))
        val ids = (1..4).map { listOf(idByName("hw_row_$it"), idByName("hw_title_$it"), idByName("hw_due_$it"), idByName("hw_dot_$it")) }
        val colors = colorsFor(context, snapshot)
        paint(views, colors, text = listOf(R.id.title) + ids.map { it[1] },
            accent = listOf(R.id.count) + ids.map { it[2] }, badges = listOf(R.id.add_homework))
        if (colors != null) ids.forEach { tint(views, it[2], colors.highlight) }

        views.setTextViewText(R.id.title, "Домашка")
        if (snapshot == null) {
            views.setTextViewText(R.id.count, "")
            for ((i, rowIds) in ids.withIndex()) {
                views.setViewVisibility(rowIds[0], if (i == 0) View.VISIBLE else View.GONE)
                views.setTextViewText(rowIds[1], if (i == 0) "Откройте приложение" else "")
                views.setTextViewText(rowIds[2], "")
                views.setViewVisibility(rowIds[2], View.GONE)
                views.setViewVisibility(rowIds[3], View.GONE)
            }
            return views
        }

        views.setTextViewText(R.id.count, if (snapshot.homeworkCount == 0) "" else WidgetLogic.tasksText(snapshot.homeworkCount))
        val today = WidgetLogic.moscowDate(nowMs)
        for ((i, rowIds) in ids.withIndex()) {
            val (row, title, due, dot) = rowIds
            val item = snapshot.homework.getOrNull(i)
            if (item == null) {
                if (i == 0) {
                    // Заданий нет — спокойное сообщение вместо пустого виджета
                    views.setViewVisibility(row, View.VISIBLE)
                    views.setTextViewText(title, "Всё сделано — можно отдыхать")
                    views.setViewVisibility(due, View.GONE)
                    views.setViewVisibility(dot, View.GONE)
                } else {
                    views.setViewVisibility(row, View.GONE)
                }
                continue
            }
            views.setViewVisibility(row, View.VISIBLE)
            views.setViewVisibility(due, View.VISIBLE)
            views.setViewVisibility(dot, View.VISIBLE)
            (toneOf(context, item.tone)?.accent ?: colors?.accent)?.let { tint(views, dot, it) }
            val text = SpannableStringBuilder(item.short)
            text.setSpan(StyleSpan(Typeface.BOLD), 0, item.short.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            if (item.text.isNotBlank()) text.append(" · ").append(item.text.replace('\n', ' '))
            views.setTextViewText(title, text)
            views.setTextViewText(due, WidgetLogic.dueLabel(item.due, today))
        }
        return views
    }
}
