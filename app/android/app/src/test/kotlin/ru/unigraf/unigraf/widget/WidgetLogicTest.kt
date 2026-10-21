package ru.unigraf.unigraf.widget

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Проверка логики виджетов на контрольных фактах: среда 7 октября 2026 у 1 БИ-25, подгруппа 1 (АРХИТЕКТУРА.md, §11). */
class WidgetLogicTest {
    private fun lesson(start: String, end: String, pair: Int, short: String, room: String, kind: String, homework: Boolean = false) =
        """{"start":"$start","end":"$end","pair":$pair,"short":"$short","subject":"$short","room":"$room","teacher":null,"kind":"$kind","hasHomework":$homework}"""

    private val json = """
    {"generatedAt":"2026-10-07T08:00+03:00","weekLabel":"2 неделя","days":[
      {"date":"2026-10-07","lessons":[
        ${lesson("2026-10-07T13:00+03:00", "2026-10-07T14:30+03:00", 3, "Технол. предпр.", "2-05", "lecture")},
        ${lesson("2026-10-07T14:40+03:00", "2026-10-07T16:10+03:00", 4, "ЧТК и этика", "2-15", "practice", true)}
      ]},
      {"date":"2026-10-08","lessons":[
        ${lesson("2026-10-08T09:00+03:00", "2026-10-08T10:30+03:00", 1, "Управ. проектами", "2-21", "practice")}
      ]},
      {"date":"2026-10-09","lessons":[]}
    ]}"""
    private val snapshot = WidgetLogic.parse(json)

    private fun t(moment: String) = WidgetLogic.parseMoment(moment)

    @Test
    fun parsesSnapshot() {
        assertEquals("2 неделя", snapshot.weekLabel)
        assertEquals(3, snapshot.days.size)
        assertEquals(3, snapshot.allLessons.size)
        val chtk = snapshot.allLessons[1]
        assertEquals("2-15", chtk.room)
        assertEquals("П", chtk.kindLetter)
        assertTrue(chtk.hasHomework)
        assertNull(chtk.teacher)
    }

    @Test
    fun assessmentKindsHaveLetters() {
        val letters = listOf("attestation", "credit", "exam").map {
            WidgetLogic.parse("""{"weekLabel":"1 неделя","days":[{"date":"2026-10-12","lessons":[${lesson("2026-10-12T09:00+03:00", "2026-10-12T10:30+03:00", 1, "ЧТК", "2-15", it)}]}]}""")
                .allLessons.single().kindLetter
        }
        assertEquals(listOf("А", "З", "Э"), letters)
    }

    @Test
    fun parsesToneAndChangedFlag() {
        val withTone = WidgetLogic.parse(
            """{"weekLabel":"1 неделя","days":[{"date":"2026-10-12","lessons":[
              {"start":"2026-10-12T09:00+03:00","end":"2026-10-12T10:30+03:00","pair":1,"short":"Филос.","subject":"Философия","room":"3-01","teacher":null,"kind":"lecture",
               "changed":true,
               "tone":{"light":{"accent":"#7A8A12","container":"#EBF0C6","onContainer":"#3D4314"},"dark":{"accent":"#CBD870","container":"#3B4306","onContainer":"#EDF1D0"}}},
              {"start":"2026-10-12T10:40+03:00","end":"2026-10-12T12:10+03:00","pair":2,"short":"Мат.","subject":"Математика","room":"3-03","teacher":null,"kind":"practice"}
            ]}]}""",
        )
        val first = withTone.allLessons[0]
        assertTrue(first.changed)
        assertEquals(WidgetLogic.parseHex("#7A8A12"), first.tone!!.pick(night = false).accent)
        assertEquals(WidgetLogic.parseHex("#CBD870"), first.tone!!.pick(night = true).accent)
        assertEquals(WidgetLogic.parseHex("#3D4314"), first.tone!!.light.onContainer)
        // Старые снимки без новых полей читаются как раньше: не изменена, цвета предмета нет
        val second = withTone.allLessons[1]
        assertFalse(second.changed)
        assertNull(second.tone)
    }

    @Test
    fun momentsAreInUtc() {
        // 13:00 по Москве = 10:00 UTC
        assertEquals(1791367200000L, t("2026-10-07T13:00+03:00"))
        assertEquals(t("2026-10-07T10:00+00:00"), t("2026-10-07T13:00+03:00"))
    }

    @Test
    fun beforeFirstPairShowsItAsNext() {
        val state = WidgetLogic.nowNext(snapshot, t("2026-10-07T12:00+03:00"))
        assertFalse(state.isCurrent)
        assertEquals("2-05", state.lesson?.room)
    }

    @Test
    fun duringPairShowsItAsCurrent() {
        val state = WidgetLogic.nowNext(snapshot, t("2026-10-07T13:10+03:00"))
        assertTrue(state.isCurrent)
        assertEquals("Технол. предпр.", state.lesson?.short)
    }

    @Test
    fun pairBoundariesSwitchExactlyOnTheBell() {
        // 14:30:00 — первая пара кончилась, идёт перемена → «далее» ЧТК
        val atEnd = WidgetLogic.nowNext(snapshot, t("2026-10-07T14:30+03:00"))
        assertFalse(atEnd.isCurrent)
        assertEquals("ЧТК и этика", atEnd.lesson?.short)
        // 14:40:00 — началась вторая
        val atStart = WidgetLogic.nowNext(snapshot, t("2026-10-07T14:40+03:00"))
        assertTrue(atStart.isCurrent)
        assertEquals("ЧТК и этика", atStart.lesson?.short)
    }

    @Test
    fun afterLastPairShowsTomorrowsFirst() {
        val state = WidgetLogic.nowNext(snapshot, t("2026-10-07T16:15+03:00"))
        assertFalse(state.isCurrent)
        assertEquals("2-21", state.lesson?.room)
    }

    @Test
    fun nothingLeftInSnapshot() {
        val state = WidgetLogic.nowNext(snapshot, t("2026-10-08T11:00+03:00"))
        assertNull(state.lesson)
    }

    @Test
    fun todayViewShowsTodayWhileLessonsRemain() {
        val view = WidgetLogic.todayView(snapshot, t("2026-10-07T12:00+03:00"))
        assertTrue(view.isToday)
        assertEquals(2, view.lessons.size)
        // Во время последней пары — всё ещё сегодня
        assertTrue(WidgetLogic.todayView(snapshot, t("2026-10-07T15:00+03:00")).isToday)
    }

    @Test
    fun todayViewSwitchesToTomorrowAfterLastPair() {
        val view = WidgetLogic.todayView(snapshot, t("2026-10-07T16:10+03:00"))
        assertFalse(view.isToday)
        assertEquals("2026-10-08", view.date)
        assertEquals(1, view.lessons.size)
    }

    @Test
    fun todayViewSkipsEmptyDays() {
        // 8 октября после пары: 9 октября пусто, дальше в снимке ничего — остаётся сегодняшний (уже прошедший) день
        val view = WidgetLogic.todayView(snapshot, t("2026-10-08T12:00+03:00"))
        assertTrue(view.isToday)
    }

    @Test
    fun nextBoundaryIsNearestStartOrEnd() {
        assertEquals(t("2026-10-07T13:00+03:00"), WidgetLogic.nextBoundary(snapshot, t("2026-10-07T12:00+03:00")))
        assertEquals(t("2026-10-07T14:30+03:00"), WidgetLogic.nextBoundary(snapshot, t("2026-10-07T13:10+03:00")))
        assertEquals(t("2026-10-07T14:40+03:00"), WidgetLogic.nextBoundary(snapshot, t("2026-10-07T14:30+03:00")))
        assertEquals(t("2026-10-08T09:00+03:00"), WidgetLogic.nextBoundary(snapshot, t("2026-10-07T16:10+03:00")))
        assertNull(WidgetLogic.nextBoundary(snapshot, t("2026-10-08T10:30+03:00")))
    }

    @Test
    fun moscowDateRollsOverAtMoscowMidnight() {
        // 21:30 UTC 7 октября = 00:30 МСК 8 октября
        assertEquals("2026-10-08", WidgetLogic.moscowDate(t("2026-10-07T21:30+00:00")))
        assertEquals("2026-10-07", WidgetLogic.moscowDate(t("2026-10-07T20:59+00:00")))
    }

    @Test
    fun weekdayNamesAreRussian() {
        assertEquals("Четверг", WidgetLogic.weekdayName("2026-10-08"))
        assertEquals("Воскресенье", WidgetLogic.weekdayName("2026-10-11"))
    }

    @Test
    fun minutesText() {
        assertEquals("12 мин", WidgetLogic.minutesText(12 * 60_000L))
        assertEquals("1 ч 30 мин", WidgetLogic.minutesText(90 * 60_000L))
        assertEquals("0 мин", WidgetLogic.minutesText(-5))
    }

    // ---------- новые виджеты ----------

    private val richJson = """
    {"generatedAt":"2026-10-07T08:00+03:00","weekLabel":"2 неделя","homeworkCount":3,
     "homework":[
       {"subject":"Физика","short":"Физика","text":"Задачи 4–9","due":"2026-10-08","files":1},
       {"subject":"Философия","short":"Философия","text":"Конспект","due":"2026-10-14","files":0}],
     "colors":{
       "light":{"bg":"#FBF8F3","text":"#1B1C1A","textSecondary":"#51565A","accent":"#0B5563","highlight":"#CDEBF0","badgeBg":"#FFDDA8","badgeText":"#2B1A00"},
       "dark":{"bg":"#172023","text":"#E3E7E8","textSecondary":"#B5BEC0","accent":"#7FD3E0","highlight":"#0F4A55","badgeBg":"#5E4100","badgeText":"#FFDDA8"}},
     "days":[
      {"date":"2026-10-07","lessons":[
        ${lesson("2026-10-07T13:00+03:00", "2026-10-07T14:30+03:00", 3, "Технол. предпр.", "2-05", "lecture")},
        ${lesson("2026-10-07T14:40+03:00", "2026-10-07T16:10+03:00", 4, "ЧТК и этика", "2-15", "practice")}]},
      {"date":"2026-10-08","lessons":[
        ${lesson("2026-10-08T09:00+03:00", "2026-10-08T10:30+03:00", 1, "Управ. проектами", "2-21", "practice")}]},
      {"date":"2026-10-09","lessons":[]}]}"""
    private val rich = WidgetLogic.parse(richJson)

    @Test
    fun parsesHomeworkAndColors() {
        assertEquals(3, rich.homeworkCount)
        assertEquals(2, rich.homework.size)
        assertEquals("Физика", rich.homework[0].short)
        assertEquals(1, rich.homework[0].files)
        assertEquals(0xFF0B5563.toInt(), rich.lightColors?.accent)
        assertEquals(0xFF7FD3E0.toInt(), rich.darkColors?.accent)
    }

    @Test
    fun oldSnapshotWithoutNewFieldsStillWorks() {
        assertEquals(0, snapshot.homeworkCount)
        assertTrue(snapshot.homework.isEmpty())
        assertNull(snapshot.lightColors)
    }

    @Test
    fun brokenColorsAreIgnored() {
        val broken = WidgetLogic.parse("""{"weekLabel":"","days":[],"colors":{"light":{"bg":"zzz"}}}""")
        assertNull(broken.lightColors)
    }

    @Test
    fun tomorrowShowsNextDayLessons() {
        val view = WidgetLogic.tomorrowView(rich, t("2026-10-07T15:00+03:00"))
        assertEquals("2026-10-08", view.date)
        assertEquals(1, view.lessons.size)
        assertEquals("2-21", view.lessons[0].room)
    }

    @Test
    fun tomorrowWithoutLessonsIsEmpty() {
        assertTrue(WidgetLogic.tomorrowView(rich, t("2026-10-08T12:00+03:00")).lessons.isEmpty())
    }

    @Test
    fun weekRowsSummarizeEachDay() {
        val rows = WidgetLogic.weekRows(rich, t("2026-10-07T15:00+03:00"))
        assertEquals(3, rows.size)
        assertEquals("Ср 7", rows[0].dayLabel)
        assertEquals(2, rows[0].count)
        assertEquals("13:00–16:10", rows[0].range)
        assertTrue(rows[0].isToday)
        assertFalse(rows[1].isToday)
        assertEquals("Пт 9", rows[2].dayLabel)
        assertEquals(0, rows[2].count)
        assertEquals("", rows[2].range)
    }

    @Test
    fun russianPlurals() {
        assertEquals("1 пара", WidgetLogic.pairsText(1))
        assertEquals("2 пары", WidgetLogic.pairsText(2))
        assertEquals("5 пар", WidgetLogic.pairsText(5))
        assertEquals("11 пар", WidgetLogic.pairsText(11))
        assertEquals("1 задание", WidgetLogic.tasksText(1))
        assertEquals("3 задания", WidgetLogic.tasksText(3))
        assertEquals("12 заданий", WidgetLogic.tasksText(12))
    }

    @Test
    fun homeworkDueLabels() {
        val today = "2026-10-07"
        assertEquals("просрочено", WidgetLogic.dueLabel("2026-10-06", today))
        assertEquals("сегодня", WidgetLogic.dueLabel("2026-10-07", today))
        assertEquals("завтра", WidgetLogic.dueLabel("2026-10-08", today))
        assertEquals("Ср 14", WidgetLogic.dueLabel("2026-10-14", today))
        // переход через конец месяца: завтра после 30 сентября — 1 октября
        assertEquals("завтра", WidgetLogic.dueLabel("2026-10-01", "2026-09-30"))
    }

    @Test
    fun hexColorsParse() {
        assertEquals(0xFF0B5563.toInt(), WidgetLogic.parseHex("#0B5563"))
        assertEquals(0xFFFFFFFF.toInt(), WidgetLogic.parseHex("FFFFFF"))
    }
}
