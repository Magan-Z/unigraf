// Экран «Поиск»: преподаватель (где сейчас и расписание), аудитория (пары в ней и свободные аудитории на выбранную пару),
// группа (расписание любой группы на выбранный день).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_state.dart';
import '../../core/bells.dart';
import '../../core/formatting.dart';
import '../../domain/models.dart';
import '../../domain/search.dart';
import '../../theme/app_theme.dart' show roomTextStyle;
import '../../theme/tokens.dart';
import '../common/empty_state.dart';
import '../common/illustrations.dart';
import '../common/lesson_widgets.dart';
import '../common/reveal.dart';
import '../common/sliding_segments.dart';

enum _Mode { teacher, room, group }

/// Внутри «Аудитории»: пары в одной аудитории или список свободных.
enum _RoomMode { lessons, free }

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  _Mode _mode = _Mode.teacher;
  String? _teacher;
  String? _room;
  _RoomMode _roomMode = _RoomMode.lessons;
  String? _groupId; // группа, чьё расписание показано
  int? _subgroup; // null — обе подгруппы
  int _groupField = 0; // растёт, когда группа выбрана кнопкой: поле ввода создаётся заново с её названием
  int _dayOffset = 0; // 0 — сегодня, 1 — завтра …
  int _pair = 1;

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(allGroupsProvider);
    final index = ref.watch(indexProvider).value;
    final today = ref.watch(todayProvider);

    return all.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text(
          'Не удалось прочитать расписания:\n$e',
          textAlign: TextAlign.center,
        ),
      ),
      data: (schedules) {
        if (index == null) return const SizedBox();
        final day = today.add(Duration(days: _dayOffset));
        final dayLessons = campusLessons(
          day,
          index,
          schedules,
          forcedWeek: ref.watch(settingsProvider).forcedWeek,
        );

        return ListView(
          padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.lg, Gap.lg, Gap.xl),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Gap.xs),
              child: Text(
                'Поиск',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
            const SizedBox(height: 12),
            SlidingSegments<_Mode>(
              segments: const [
                Segment(_Mode.teacher, 'Преподаватель'),
                Segment(_Mode.room, 'Аудитория'),
                Segment(_Mode.group, 'Группа'),
              ],
              selected: _mode,
              onChanged: (m) => setState(() => _mode = m),
            ),
            const SizedBox(height: 12),
            if (_mode == _Mode.room) ...[
              SlidingSegments<_RoomMode>(
                segments: const [
                  Segment(_RoomMode.lessons, 'Пары в аудитории'),
                  Segment(_RoomMode.free, 'Свободные'),
                ],
                selected: _roomMode,
                onChanged: (m) => setState(() => _roomMode = m),
              ),
              const SizedBox(height: 12),
            ],
            _DayChips(
              today: today,
              selected: _dayOffset,
              onSelected: (i) => setState(() => _dayOffset = i),
            ),
            const SizedBox(height: 12),
            // Ключ по режиму: при переключении содержимое появляется заново (волной), а не «щёлкает» на месте
            KeyedSubtree(
              key: ValueKey('$_mode-$_roomMode'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: switch (_mode) {
                  _Mode.teacher => _teacherView(
                    schedules,
                    index,
                    dayLessons,
                    day,
                  ),
                  _Mode.room => _roomMode == _RoomMode.lessons
                      ? _roomView(schedules, index, dayLessons)
                      : _freeView(schedules, index, dayLessons),
                  _Mode.group => _groupView(schedules, index, day),
                },
              ),
            ),
          ],
        );
      },
    );
  }

  // ---------- преподаватель ----------

  List<Widget> _teacherView(
    List<GroupSchedule> schedules,
    ScheduleIndex index,
    List<CampusLesson> dayLessons,
    DateTime day,
  ) {
    final directory = index.teachers;
    final names = teacherNames(schedules, directory: directory);
    final teacher = _teacher;
    final lessons = teacher == null
        ? <CampusLesson>[]
        : lessonsOfTeacher(teacher, dayLessons);
    final now = ref.watch(nowProvider).value ?? ref.read(clockProvider).now();

    return [
      Reveal(
        index: 0,
        child: _Autocomplete(
          key: const ValueKey('teacher'),
          label: 'Фамилия или имя',
          initialText: teacher,
          options: names,
          onSelected: (v) => setState(() => _teacher = v),
        ),
      ),
      const SizedBox(height: 12),
      if (teacher == null)
        const Reveal(
          index: 1,
          child: _SearchHint(
            illustration: IllustrationKind.searchTeacher,
            title: 'Найдите преподавателя',
            text:
                'Введите фамилию: покажем, где он сейчас и какие у него пары.',
          ),
        )
      else ...[
        if (_dayOffset == 0)
          Reveal(index: 1, child: _teacherNow(lessons, index, now)),
        _LessonList(
          lessons: lessons,
          index: index,
          directory: directory,
          emptyText: 'В этот день занятий нет',
          replayKey: '$teacher-$_dayOffset',
        ),
      ],
    ];
  }

  Widget _teacherNow(
    List<CampusLesson> lessons,
    ScheduleIndex index,
    DateTime now,
  ) {
    var status = 'Сейчас занятий нет';
    var live = false;
    for (final l in lessons) {
      final (start, end) = pairTimes(moscowToday(now), l.pair, index.bells);
      if (!now.isBefore(start) && now.isBefore(end)) {
        status =
            'Сейчас ведёт: ${l.subject}${l.room != null ? ' · ${l.room}' : ''}';
        live = true;
        break;
      }
      if (start.isAfter(now)) {
        status =
            'Следующая пара в ${moscowTimeText(start)}${l.room != null ? ' · ${l.room}' : ''}';
        break;
      }
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _StatusCard(text: status, live: live),
    );
  }

  // ---------- аудитория ----------

  List<Widget> _roomView(
    List<GroupSchedule> schedules,
    ScheduleIndex index,
    List<CampusLesson> dayLessons,
  ) {
    final room = _room;
    return [
      Reveal(
        index: 0,
        child: _Autocomplete(
          key: const ValueKey('room'),
          label: 'Номер аудитории, например 2-05',
          initialText: room,
          options: allRooms(schedules),
          onSelected: (v) => setState(() => _room = v),
        ),
      ),
      const SizedBox(height: 12),
      if (room == null)
        const Reveal(
          index: 1,
          child: _SearchHint(
            illustration: IllustrationKind.searchRoom,
            title: 'Пары в аудитории',
            text:
                'Введите номер, например 2-05: покажем, какие пары в ней проходят. Нужна свободная аудитория — выберите «Свободные».',
          ),
        )
      else
        _LessonList(
          lessons: lessonsInRoom(room, dayLessons),
          index: index,
          directory: index.teachers,
          emptyText: 'В этот день аудитория свободна',
          replayKey: '$room-$_dayOffset',
        ),
    ];
  }

  // ---------- группа ----------

  List<Widget> _groupView(List<GroupSchedule> schedules, ScheduleIndex index, DateTime day) {
    final infos = [for (final f in index.forms) ...f.groups];
    final schedule = _groupId == null ? null : schedules.where((s) => s.groupId == _groupId).firstOrNull;
    final theme = Theme.of(context);

    void pick(String title) {
      final found = schedules.where((s) => s.title == title).firstOrNull;
      if (found == null) return;
      setState(() {
        _groupId = found.groupId;
        _subgroup = null;
      });
    }

    return [
      Reveal(
        index: 0,
        child: _Autocomplete(
          key: ValueKey('group-$_groupField'),
          label: 'Группа, например 1 БИ-25',
          initialText: schedule?.title,
          options: [for (final g in infos) g.title],
          matches: groupMatches,
          maxOptions: 10,
          onSelected: pick,
        ),
      ),
      const SizedBox(height: 12),
      if (schedule == null) ...[
        Reveal(
          index: 1,
          child: Text(
            'Введите название группы или выберите её ниже: покажем расписание на выбранный день.',
            style: theme.textTheme.bodyMedium,
          ),
        ),
        for (final form in index.forms) ...[
          Padding(
            padding: const EdgeInsets.only(top: 20, bottom: 4),
            child: Text(form.title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          ),
          for (final course in ({for (final g in form.groups) g.course}.toList()..sort()))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 64,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text('$course курс', style: theme.textTheme.bodySmall),
                    ),
                  ),
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final g in form.groups.where((g) => g.course == course))
                          ActionChip(
                            label: Text(g.title),
                            onPressed: () {
                              pick(g.title);
                              setState(() => _groupField++);
                            },
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ] else ...[
        if (schedule.subgroups.length > 1) ...[
          Reveal(
            index: 1,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final (n, label) in [(null, 'Обе подгруппы'), for (final s in schedule.subgroups) (s.n, s.label)])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        showCheckmark: false,
                        label: Text(label),
                        selected: _subgroup == n,
                        onSelected: (_) => setState(() => _subgroup = n),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        _LessonList(
          lessons: groupLessons(
            day,
            index,
            schedule,
            subgroup: _subgroup,
            forcedWeek: ref.watch(settingsProvider).forcedWeek,
          ),
          index: index,
          directory: index.teachers,
          emptyText: 'В этот день занятий нет',
          replayKey: '${schedule.groupId}-$_dayOffset-$_subgroup',
          showGroups: false,
        ),
        const SizedBox(height: 4),
        Text(
          'Официальное расписание группы, без правок старосты и личных правок.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    ];
  }

  // ---------- свободные аудитории ----------

  List<Widget> _freeView(
    List<GroupSchedule> schedules,
    ScheduleIndex index,
    List<CampusLesson> dayLessons,
  ) {
    final free = freeRooms(_pair, dayLessons, allRooms(schedules));
    final theme = Theme.of(context);
    final bell = index.bells[_pair - 1];
    // По этажам: первая цифра номера аудитории («3-14» — 3 этаж)
    final byFloor = <String, List<String>>{};
    for (final r in free) {
      byFloor.putIfAbsent(r.substring(0, 1), () => []).add(r);
    }

    return [
      Reveal(
        index: 0,
        child: SlidingSegments<int>(
          segments: [
            for (var p = 1; p <= index.bells.length; p++) Segment(p, '$p пара'),
          ],
          selected: _pair,
          onChanged: (p) => setState(() => _pair = p),
        ),
      ),
      const SizedBox(height: 12),
      Reveal(
        index: 1,
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(text: '${bell.startText}–${bell.endText} · свободно '),
              TextSpan(
                text:
                    '${free.length} ${plural(free.length, 'аудитория', 'аудитории', 'аудиторий')}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          style: theme.textTheme.bodyMedium,
        ),
      ),
      for (final (i, entry) in byFloor.entries.indexed) ...[
        Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 8),
          child: Text(
            '${entry.key} этаж',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Reveal(
          // ключ с парой и днём: при смене пары таблички появляются заново
          key: ValueKey('floor-${entry.key}-$_pair-$_dayOffset'),
          index: i + 2,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [for (final r in entry.value) _RoomTag(r)],
          ),
        ),
      ],
      const SizedBox(height: 12),
      Text(
        'Свободной считается аудитория, в которой по расписанию нет занятий. Её могли занять без расписания — уточняйте.',
        style: theme.textTheme.bodySmall,
      ),
    ];
  }
}

/// Подсказка, пока ничего не выбрано: тот же вид, что у пустого дня на «Сегодня» (рисунок, заголовок, пояснение), по центру свободного места.
class _SearchHint extends StatelessWidget {
  const _SearchHint({required this.illustration, required this.title, required this.text});
  final IllustrationKind illustration;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    // место под полем поиска и до нижней панели (≈ 360 dp занято сверху и снизу)
    final height = (MediaQuery.sizeOf(context).height - 360).clamp(300.0, 640.0);
    return SizedBox(
      height: height,
      child: EmptyState(illustration: illustration, title: title, subtitle: text),
    );
  }
}

/// Строка состояния преподавателя: «Сейчас ведёт…» (с янтарной точкой) или «Следующая пара в…».
class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.text, required this.live});
  final String text;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.md),
      decoration: BoxDecoration(
        color: live ? scheme.tertiaryContainer : scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: live ? scheme.tertiary : scheme.outline,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: Gap.md),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: live ? scheme.onTertiaryContainer : scheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Номер свободной аудитории: маленькая «табличка», как на двери.
class _RoomTag extends StatelessWidget {
  const _RoomTag(this.room);
  final String room;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: Gap.sm),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(
          color: scheme.primary.withValues(alpha: 0.55),
          width: 1.5,
        ),
      ),
      child: Text(room, style: roomTextStyle(16, color: scheme.onSurface)),
    );
  }
}

class _DayChips extends StatelessWidget {
  const _DayChips({
    required this.today,
    required this.selected,
    required this.onSelected,
  });
  final DateTime today;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < 7; i++)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                showCheckmark: false,
                label: Text(
                  i == 0
                      ? 'Сегодня'
                      : i == 1
                      ? 'Завтра'
                      : '${weekdayShort[today.add(Duration(days: i)).weekday]} ${today.add(Duration(days: i)).day}',
                ),
                selected: selected == i,
                onSelected: (_) => onSelected(i),
              ),
            ),
        ],
      ),
    );
  }
}

class _Autocomplete extends StatelessWidget {
  const _Autocomplete({
    super.key,
    required this.label,
    required this.options,
    required this.onSelected,
    this.initialText,
    this.matches,
    this.maxOptions = 8,
  });
  final String label;
  final List<String> options;
  final ValueChanged<String> onSelected;

  /// Текст в поле при создании (выбранное раньше значение: поле пересоздаётся при смене режима).
  final String? initialText;

  /// Как отбирать подсказки; по умолчанию — запрос внутри названия без учёта регистра.
  final bool Function(String option, String query)? matches;
  final int maxOptions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) => Autocomplete<String>(
        initialValue: initialText == null ? null : TextEditingValue(text: initialText!),
        optionsBuilder: (value) {
          final q = value.text.trim().toLowerCase();
          if (q.isEmpty) return const Iterable<String>.empty();
          final test = matches ?? (String o, String query) => o.toLowerCase().contains(query);
          return options.where((o) => test(o, q)).take(maxOptions);
        },
        onSelected: onSelected,
        // Список подсказок: скруглённая карточка под полем той же ширины (а не квадрат на весь экран)
        optionsViewBuilder: (context, onPick, items) => Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.only(top: Gap.xs),
            child: Material(
              elevation: 4,
              shadowColor: Colors.black54,
              color: scheme.surfaceContainerHigh,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md)),
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: constraints.maxWidth, maxHeight: 320),
                child: SizedBox(
                  width: constraints.maxWidth,
                  child: ListView(
                    padding: const EdgeInsets.symmetric(vertical: Gap.xs),
                    shrinkWrap: true,
                    children: [
                      for (final o in items)
                        InkWell(
                          onTap: () => onPick(o),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: minTouch),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.md),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(o, style: theme.textTheme.bodyLarge),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        fieldViewBuilder: (context, controller, focus, submit) => TextField(
          controller: controller,
          focusNode: focus,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.search),
          ),
        ),
      ),
    );
  }
}

class _LessonList extends StatelessWidget {
  const _LessonList({
    required this.lessons,
    required this.index,
    required this.directory,
    required this.emptyText,
    required this.replayKey,
    this.showGroups = true,
  });

  /// В подвале карточки: список групп (поиск по институту) или только пометка занятия (расписание одной группы).
  final bool showGroups;
  final List<CampusLesson> lessons;
  final ScheduleIndex index;
  final List<String> directory; // полные ФИО преподавателей
  final String emptyText;

  /// Что именно показано (кто и в какой день): при смене пары появляются заново.
  final String replayKey;

  @override
  Widget build(BuildContext context) {
    if (lessons.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: Gap.lg),
        child: Row(
          children: [
            Icon(
              Icons.event_available_rounded,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: Gap.sm),
            Flexible(
              child: Text(
                emptyText,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        for (final (i, l) in lessons.indexed)
          Reveal(
            key: ValueKey(
              '$replayKey-${l.pair}-${l.subject}-${l.teacher}-${l.room}-${l.note}-${l.groups.join(',')}',
            ),
            index: i + 2,
            child: Padding(
              padding: const EdgeInsets.only(bottom: Gap.sm),
              child: LessonTile(
                timeLabel:
                    '${index.bells[l.pair - 1].startText}–${index.bells[l.pair - 1].endText} · ${l.pair} пара',
                subject: l.subject,
                kind: l.kind,
                teacher: l.teacher == null
                    ? null
                    : teacherFullName(l.teacher!, directory),
                room: l.room,
                footer: showGroups ? l.groups.join(', ') : l.note,
              ),
            ),
          ),
      ],
    );
  }
}
