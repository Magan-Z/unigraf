// Настройки: сгруппированы по смыслу — профиль, оформление, расписание, уведомления, данные, о приложении.
// Значения выбираются в нижнем окне со списком (удобно пальцем и не ломается при крупном шрифте).

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_state.dart';
import '../../core/formatting.dart';
import '../../domain/homework.dart';
import '../../domain/models.dart';
import '../../theme/next_design.dart';
import '../../theme/tokens.dart';
import '../../config.dart';
import '../../data/remote/shared_api.dart';
import '../../domain/group_shared.dart';
import '../../group_actions.dart';
import 'group_changes_screen.dart';
import 'palette_picker.dart';
import 'subjects_screen.dart';
import '../common/brand_mark.dart';
import '../common/widget_picker.dart';
import '../onboarding/onboarding_screen.dart';
import '../../domain/teacher.dart';
import '../../update_check.dart';
import '../update_banner.dart';
import '../teacher/teacher_code_dialog.dart';
import '../teacher/teacher_picker.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final profile = settings.profile;
    final index = ref.watch(indexProvider).value;
    final group = profile == null ? null : index?.findGroup(profile.groupId);
    final today = ref.watch(todayProvider);
    final fetched = ref.watch(lastFetchedProvider).value;
    final now = ref.watch(nowProvider).value ?? ref.read(clockProvider).now();
    final theme = Theme.of(context);
    final appVer = ref.watch(appVersionProvider);
    final updateInfo = ref.watch(updateInfoProvider);
    // новая версия есть, даже если плашку на главном экране уже закрыли
    final newVersion = updateInfo != null && computeUpdateStatus(current: appVer, info: updateInfo) != UpdateStatus.none ? updateInfo.latest : null;

    final autoWeek = index == null ? null : (today.difference(index.weekAnchor).inDays / 7).floor() % 2 + 1;

    return ListView(
      padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.lg, Gap.lg, Gap.xxl),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Gap.xs),
          child: Text('Настройки', style: theme.textTheme.headlineMedium),
        ),
        const SizedBox(height: Gap.lg),
        if (kTestBadge) ...[
          // Тестовое оформление: понятно, что это пробная версия, и где обычная
          Container(
            padding: const EdgeInsets.all(Gap.lg),
            decoration: BoxDecoration(color: theme.colorScheme.tertiaryContainer, borderRadius: BorderRadius.circular(Radii.lg)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.science_rounded, color: theme.colorScheme.onTertiaryContainer),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Text(
                  'Тестовый вид. Расписание и функции те же, пробуется только новое оформление и анимации. '
                  'Обычная версия открывается по адресу без «-next».',
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onTertiaryContainer),
                ),
              ),
            ]),
          ),
          const SizedBox(height: Gap.lg),
        ],

        if (settings.isTeacher)
          _Section(title: 'Профиль', children: [
            _Row(
              icon: Icons.school_rounded,
              title: settings.teacherName ?? 'Преподаватель',
              subtitle: 'Сменить преподавателя (кто вы в списке)',
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const TeacherPickerScreen())),
            ),
            _Row(
              icon: Icons.groups_rounded,
              title: 'Режим студента',
              subtitle: 'Вернуться к расписанию своей группы',
              onTap: () => notifier.setRole(UserRole.student),
            ),
          ])
        else
        _Section(title: 'Профиль', children: [
          _Row(
            icon: Icons.groups_rounded,
            title: group?.title ?? 'Группа не выбрана',
            subtitle: 'Сменить группу',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OnboardingScreen(changing: true))),
          ),
          if (group != null && group.subgroups.length > 1 && profile != null)
            _Row(
              icon: Icons.person_rounded,
              title: 'Подгруппа',
              value: group.subgroups.firstWhere((s) => s.n == profile.subgroup, orElse: () => group.subgroups.first).label,
              onTap: () async {
                final picked = await _choose<int>(context, 'Подгруппа', {for (final s in group.subgroups) s.n: s.label}, profile.subgroup);
                if (picked != null) notifier.setProfile(profile.copyWith(subgroup: picked));
              },
            ),
          if (group != null && group.hasGenderedPe && profile != null)
            _Row(
              icon: Icons.sports_rounded,
              title: 'Физкультура',
              value: profile.pe.title,
              onTap: () async {
                final picked = await _choose<PeChoice>(context, 'Физкультура', {for (final p in PeChoice.values) p: p.title}, profile.pe);
                if (picked != null) notifier.setProfile(profile.copyWith(pe: picked));
              },
            ),
          _Row(
            icon: Icons.school_rounded,
            title: 'Я преподаватель',
            subtitle: 'Расписание всех ваших групп и отправка ДЗ студентам',
            onTap: () async {
              if (settings.teacherName != null) {
                await notifier.setRole(UserRole.teacher);
              } else {
                await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const TeacherPickerScreen()));
              }
            },
          ),
        ]),

        _Section(title: 'Оформление', children: [
          _Row(
            icon: Icons.brightness_6_rounded,
            title: 'Тема',
            value: const {ThemeMode.system: 'Системная', ThemeMode.light: 'Светлая', ThemeMode.dark: 'Тёмная'}[settings.themeMode],
            onTap: () async {
              final picked = await _choose<ThemeMode>(
                context,
                'Тема',
                const {ThemeMode.system: 'Системная', ThemeMode.light: 'Светлая', ThemeMode.dark: 'Тёмная'},
                settings.themeMode,
              );
              if (picked != null) notifier.setThemeMode(picked);
            },
          ),
          // Цветовая тема: наглядные карточки. Если включены цвета из обоев, они главнее
          if (!settings.useDynamicColor) PalettePicker(selected: settings.palette, amoled: settings.amoled, onSelected: notifier.setPalette),
          _SwitchRow(
            icon: Icons.contrast_rounded,
            title: 'Чёрный фон',
            subtitle: 'Для тёмной темы: экран OLED экономит заряд, а карточки ярче выделяются',
            value: settings.amoled,
            onChanged: notifier.setAmoled,
          ),
          if (!kIsWeb)
            _SwitchRow(
            icon: Icons.palette_rounded,
            title: 'Цвета из обоев',
            subtitle: 'Material You, Android 12 и новее. Выключено — фирменные цвета приложения',
            value: settings.useDynamicColor,
            onChanged: notifier.setUseDynamicColor,
          ),
        ]),

        _Section(title: 'Предметы', children: [
          _SwitchRow(
            icon: Icons.label_rounded,
            title: 'Свои названия и цвета',
            subtitle: 'Сокращайте длинные названия и выбирайте цвет для каждого предмета. Выключено — как в расписании',
            value: settings.customSubjects,
            onChanged: notifier.setCustomSubjects,
          ),
          _Row(
            icon: Icons.color_lens_rounded,
            title: 'Настроить предметы',
            subtitle: 'Название и цвет каждого предмета вашей группы',
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SubjectsScreen())),
          ),
        ]),

        if (sharedApiUrl.isNotEmpty) settings.isTeacher ? const _TeacherSection() : const _StarostaSection(),

        if (!kIsWeb)
          _Section(title: 'Виджеты', children: [
            _Row(
              icon: Icons.widgets_rounded,
              title: 'Добавить виджет',
              subtitle: 'Расписание на главном экране телефона: выберите вид',
              onTap: () => showWidgetPicker(context),
            ),
          ]),

        _Section(title: 'Расписание', children: [
          _Row(
            icon: Icons.swap_horiz_rounded,
            title: 'Номер недели',
            subtitle: settings.forcedWeek == null
                ? 'Считается автоматически${autoWeek == null ? '' : ' (сейчас $autoWeek неделя)'}. Переключите вручную, если в институте чередование сбилось'
                : 'Выбрана вручную: ${settings.forcedWeek} неделя',
            value: settings.forcedWeek == null ? 'Авто' : '${settings.forcedWeek} неделя',
            onTap: () async {
              final picked = await _choose<int>(context, 'Номер недели', const {0: 'Авто', 1: '1 неделя', 2: '2 неделя'}, settings.forcedWeek ?? 0);
              if (picked != null) notifier.setForcedWeek(picked == 0 ? null : picked);
            },
          ),
          _Row(
            icon: Icons.sync_rounded,
            title: 'Обновить расписание',
            subtitle: fetched == null ? 'Пока без обновлений с сайта: показано расписание от ${_scheduleDateText(ref)}' : 'Обновлено ${agoText(fetched, now)}',
            onTap: () async {
              final result = await syncSchedule(ProviderScope.containerOf(context));
              if (!context.mounted) return;
              final text = result.error != null ? 'Нет связи с сервером — работаем с сохранённым расписанием' : 'Расписание актуально';
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
            },
          ),
        ]),

        // В браузере (iPhone) запланировать уведомление нельзя — честно говорим об этом и подсказываем замену
        if (kIsWeb)
          const _Section(title: 'Уведомления', children: [
            _Row(
              icon: Icons.notifications_off_rounded,
              title: 'Напоминаний в браузере нет',
              subtitle: 'Браузер не умеет ставить напоминания о парах. Чтобы получать оповещения, подпишитесь на календарь: ссылка есть на сайте расписания',
            ),
          ])
        else
          _Section(title: 'Уведомления', children: [
            _Row(
              icon: Icons.notifications_rounded,
              title: 'Напоминание перед парой',
              value: settings.notifyBeforeMin == 0 ? 'Выключено' : 'За ${settings.notifyBeforeMin} мин',
              onTap: () async {
                final picked = await _choose<int>(
                  context,
                  'Напоминание перед парой',
                  const {0: 'Выключено', 5: 'За 5 минут', 10: 'За 10 минут', 15: 'За 15 минут', 30: 'За 30 минут'},
                  const [0, 5, 10, 15, 30].contains(settings.notifyBeforeMin) ? settings.notifyBeforeMin : 10,
                );
                if (picked != null) notifier.setNotifyBeforeMin(picked);
              },
            ),
            _SwitchRow(
              icon: Icons.assignment_late_rounded,
              title: 'Вечером напоминать о ДЗ',
              subtitle: 'В 19:00, если на завтра есть невыполненные задания',
              value: settings.eveningHomeworkReminder,
              onChanged: notifier.setEveningHomeworkReminder,
            ),
            Consumer(builder: (context, ref, _) {
              return _Row(
                icon: Icons.notifications_active_rounded,
                title: 'Разрешить уведомления',
                subtitle: 'Если уведомления не приходят — нажмите, чтобы разрешить их в системе',
                onTap: () async {
                  var allowed = false;
                  var opened = false;
                  try {
                    final gateway = ref.read(notificationGatewayProvider);
                    await gateway.init();
                    allowed = await gateway.requestPermission() || await gateway.areEnabled();
                    // Если окно с вопросом Android уже не показывает — сразу открываем страницу уведомлений приложения в настройках телефона
                    if (!allowed) opened = await gateway.openSystemSettings();
                  } catch (_) {}
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(allowed
                        ? 'Уведомления разрешены'
                        : opened
                            ? 'Включите «Показывать уведомления» на открывшейся странице'
                            : 'Уведомления запрещены. Включите их в настройках телефона: Приложения → UniGraf → Уведомления'),
                  ));
                },
              );
            }),
          ]),

        _Section(title: 'Данные', children: [
          _Row(
            icon: Icons.upload_rounded,
            title: 'Экспорт ДЗ',
            subtitle: 'Скопировать все ДЗ в буфер обмена — например, чтобы сохранить в заметках или отправить себе',
            onTap: () async {
              final items = await ref.read(homeworkRepositoryProvider).all();
              await Clipboard.setData(ClipboardData(text: exportHomework(items)));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Скопировано ДЗ: ${items.length}')));
            },
          ),
          _Row(
            icon: Icons.download_rounded,
            title: 'Импорт ДЗ',
            subtitle: 'Вставить ДЗ, скопированные раньше (на новом телефоне)',
            onTap: () async {
              final clip = await Clipboard.getData(Clipboard.kTextPlain);
              String message;
              try {
                final added = await ref.read(homeworkRepositoryProvider).importItems(importHomework(clip?.text ?? ''));
                ref.invalidate(homeworkProvider);
                message = 'Добавлено ДЗ: $added';
              } on FormatException catch (e) {
                message = '${e.message}. Сначала скопируйте текст экспорта.';
              }
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
            },
          ),
        ]),

        _Section(title: 'О приложении', children: [
          if (newVersion != null)
            ListTile(
              leading: const Icon(Icons.system_update_outlined),
              title: Text('Доступна версия $newVersion'),
              subtitle: const Text('Настройки и ДЗ сохранятся'),
              trailing: TextButton(onPressed: () => openUpdateDownload(context, ref), child: const Text('Скачать')),
            ),
          Padding(
            padding: const EdgeInsets.all(Gap.lg),
            child: Row(children: [
              const BrandMark(size: 56),
              const SizedBox(width: Gap.lg),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('UniGraf', style: theme.textTheme.titleMedium),
                  const SizedBox(height: Gap.xs),
                  Text(
                    '${appVer.isEmpty ? '' : 'Версия приложения: $appVer\n'}Версия расписания: ${index?.version.substring(0, 10) ?? '—'}\nБез аккаунтов и рекламы: домашка и правки хранятся только на вашем телефоне.',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ]),
              ),
            ]),
          ),
        ]),
      ],
    );
  }
}

/// Нижнее окно со списком вариантов (радиокнопки). Возвращает выбранное значение или null.
Future<T?> _choose<T>(BuildContext context, String title, Map<T, String> options, T current) {
  return showModalBottomSheet<T>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.xl, 0, Gap.xl, Gap.sm),
            child: Text(title, style: Theme.of(sheetContext).textTheme.titleLarge),
          ),
          RadioGroup<T>(
            groupValue: current,
            onChanged: (v) => Navigator.of(sheetContext).pop(v),
            child: Column(children: [
              for (final entry in options.entries) RadioListTile<T>(value: entry.key, title: Text(entry.value)),
            ]),
          ),
          const SizedBox(height: Gap.sm),
        ]),
      ),
    ),
  );
}

/// Раздел настроек: подпись и скруглённая карточка со строками.
/// «Староста и группа»: выключатель правок старосты, ввод кода и управление для самого старосты.
/// «9 октября» — дата показанного расписания (из его версии); если не разобрать — «из памяти приложения».
String _scheduleDateText(WidgetRef ref) {
  final date = scheduleDate(ref.watch(myScheduleProvider).value?.schedule.version);
  return date == null ? 'из памяти приложения' : dateText(date);
}

class _StarostaSection extends ConsumerWidget {
  const _StarostaSection();

  Future<void> _enterCode(BuildContext context, WidgetRef ref) async {
    final container = ProviderScope.containerOf(context);
    final session = await showDialog<EditorSession>(context: context, builder: (_) => _CodeDialog(container: container));
    if (session == null || !context.mounted) return;
    await syncGroupShared(container);
    if (!context.mounted) return;
    final groupId = ref.read(settingsProvider).profile?.groupId;
    final title = ref.read(indexProvider).value?.findGroup(session.groupId)?.title ?? session.groupId;
    final other = groupId != session.groupId ? ' Чтобы редактировать, выберите эту группу в «Профиле».' : '';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Вы староста группы $title.$other')));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final editor = ref.watch(editorProvider);
    final title = editor == null ? null : (ref.watch(indexProvider).value?.findGroup(editor.groupId)?.title ?? editor.groupId);

    return _Section(title: 'Староста и группа', children: [
      _SwitchRow(
        icon: Icons.groups_rounded,
        title: 'Правки и ДЗ старосты',
        subtitle: 'Показывать то, что староста поменял и задал для всей группы',
        value: settings.showGroupData,
        onChanged: notifier.setShowGroupData,
      ),
      if (editor == null)
        _Row(
          icon: Icons.admin_panel_settings_rounded,
          title: 'Я староста',
          subtitle: 'Ввести код, который вам выдали для вашей группы',
          onTap: () => _enterCode(context, ref),
        )
      else ...[
        _Row(
          icon: Icons.verified_rounded,
          title: 'Вы староста: $title',
          subtitle: 'Нажмите на пару на экране «Сегодня» — там действия «Для всей группы». ДЗ для всех — в окне «Добавить ДЗ»',
        ),
        _Row(
          icon: Icons.edit_note_rounded,
          title: 'Изменения для группы',
          subtitle: 'Что вы поменяли и задали для всех; можно удалить',
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const GroupChangesScreen())),
        ),
        _Row(
          icon: Icons.logout_rounded,
          title: 'Выйти из режима старосты',
          subtitle: 'На этом телефоне. Код можно будет ввести снова только после того, как его выдадут заново',
          onTap: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Выйти из режима старосты?'),
                content: const Text('Правки и ДЗ группы останутся, но менять их с этого телефона больше нельзя. Тот же код второй раз ввести не получится — понадобится новый.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
                  FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Выйти')),
                ],
              ),
            );
            if (ok == true) await ref.read(editorProvider.notifier).clear();
          },
        ),
      ],
    ]);
  }
}

/// Окно ввода кода старосты.
class _CodeDialog extends StatefulWidget {
  const _CodeDialog({required this.container});
  final ProviderContainer container;

  @override
  State<_CodeDialog> createState() => _CodeDialogState();
}

class _CodeDialogState extends State<_CodeDialog> {
  final _code = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_code.text.trim().isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final session = await GroupEditorActions.redeem(widget.container, _code.text);
      if (mounted) Navigator.of(context).pop(session);
    } on SharedApiException catch (e) {
      if (mounted) setState(() {
        _busy = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Код старосты'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Введите код, который вам выдали для вашей группы.'),
        const SizedBox(height: Gap.md),
        TextField(
          controller: _code,
          autofocus: true,
          enabled: !_busy,
          textCapitalization: TextCapitalization.characters,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(labelText: 'Код', errorText: _error, errorMaxLines: 3),
        ),
      ]),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(), child: const Text('Отмена')),
        FilledButton(onPressed: _busy ? null : _submit, child: Text(_busy ? 'Проверяем…' : 'Подтвердить')),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.xl),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Gap.sm, 0, Gap.sm, Gap.sm),
          child: Text(title.toUpperCase(), style: theme.textTheme.labelSmall?.copyWith(color: scheme.primary, letterSpacing: 1.2)),
        ),
        Material(
          color: scheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg)),
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) Divider(indent: Gap.lg + 40 + Gap.lg, color: scheme.outlineVariant.withValues(alpha: 0.6)),
              children[i],
            ],
          ]),
        ),
      ]),
    );
  }
}

/// Круглая плашка со значком слева — единый «ключ» всех строк.
class _IconBadge extends StatelessWidget {
  const _IconBadge(this.icon);
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(color: scheme.primaryContainer, shape: BoxShape.circle),
        child: Icon(icon, size: 22, color: scheme.onPrimaryContainer),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.title, this.subtitle, this.value, this.onTap});
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.md),
          child: Row(children: [
            _IconBadge(icon),
            const SizedBox(width: Gap.lg),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: theme.textTheme.titleSmall?.copyWith(fontSize: 16)),
                // Текущее значение — отдельной цветной строкой под названием: не сжимает название и читается при любом шрифте
                if (value != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(value!, style: theme.textTheme.labelLarge?.copyWith(color: scheme.primary)),
                  ),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(subtitle!, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                  ),
              ]),
            ),
            if (onTap != null) Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
          ]),
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({required this.icon, required this.title, this.subtitle, required this.value, required this.onChanged});
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MergeSemantics(
      child: InkWell(
        onTap: () => onChanged(!value),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.md),
            child: Row(children: [
              _IconBadge(icon),
              const SizedBox(width: Gap.lg),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: theme.textTheme.titleSmall?.copyWith(fontSize: 16)),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(subtitle!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    ),
                ]),
              ),
              const SizedBox(width: Gap.sm),
              Switch(value: value, onChanged: onChanged),
            ]),
          ),
        ),
      ),
    );
  }
}

/// «Преподаватель»: ввод кода (чтобы отправлять ДЗ студентам) и выход из режима отправки.
class _TeacherSection extends ConsumerWidget {
  const _TeacherSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(teacherSessionProvider);
    final titles = {for (final f in ref.watch(indexProvider).value?.forms ?? const <FormInfo>[]) for (final g in f.groups) g.id: g.title};
    return _Section(title: 'Преподаватель', children: [
      if (session == null)
        _Row(
          icon: Icons.vpn_key_rounded,
          title: 'Ввести код преподавателя',
          subtitle: 'С кодом можно отправлять ДЗ студентам. Код выдаёт автор приложения',
          onTap: () async {
            final got = await showTeacherCodeDialog(context);
            if (got == null || !context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Код принят: ${got.teacher}. Вкладка «ДЗ» теперь отправляет задания студентам')));
          },
        )
      else ...[
        _Row(
          icon: Icons.verified_rounded,
          title: 'Код принят: ${session.teacher}',
          subtitle: 'Групп, которым можно отправлять ДЗ: ${session.groups.length}'
              '${session.groups.isEmpty ? '' : ' (${session.groups.take(4).map((g) => titles[g] ?? g).join(', ')}${session.groups.length > 4 ? '…' : ''})'}',
        ),
        _Row(
          icon: Icons.logout_rounded,
          title: 'Выйти из режима отправки',
          subtitle: 'На этом телефоне. Отправленные ДЗ останутся у студентов. Тот же код второй раз ввести не получится',
          onTap: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Выйти из режима отправки?'),
                content: const Text('Отправленные ДЗ останутся у студентов, но отправлять и менять их с этого телефона больше нельзя. Тот же код второй раз ввести не получится: понадобится новый.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
                  FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Выйти')),
                ],
              ),
            );
            if (ok == true) await ref.read(teacherSessionProvider.notifier).clear();
          },
        ),
      ],
    ]);
  }
}
