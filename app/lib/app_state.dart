// Состояние приложения (Riverpod): настройки, расписание, «сейчас», синхронизация.
// Экраны только читают эти провайдеры — логика живёт здесь и в domain/.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';
import 'data/remote/shared_api.dart';
import 'data/repositories/group_shared_repository.dart';
import 'domain/group_shared.dart';
import 'core/bells.dart';
import 'core/clock.dart';
import 'core/week.dart';
import 'data/attachments/attachment_store.dart';
import 'widget_bridge/widget_pinner.dart';
import 'data/attachments/group_files.dart';
import 'data/local/database.dart';
import 'data/remote/schedule_api.dart';
import 'data/repositories/homework_repository.dart';
import 'data/repositories/overrides_repository.dart';
import 'data/repositories/schedule_repository.dart';
import 'data/repositories/subject_styles_repository.dart';
import 'domain/diff_summary.dart';
import 'domain/homework.dart';
import 'domain/models.dart';
import 'domain/subject_styles.dart';
import 'domain/teacher.dart';
import 'domain/teacher_homework.dart';
import 'notifications/notification_gateway.dart';
import 'theme/brand_colors.dart';
import 'widget_bridge/deep_links.dart';
import 'widget_bridge/widget_sync.dart';

// ---------- базовые зависимости (в тестах подменяются) ----------

final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('SharedPreferences передаётся в main()'),
);

final clockProvider = Provider<Clock>((ref) => const SystemClock());

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final repositoryProvider = Provider<ScheduleRepository>((ref) => ScheduleRepository(
      db: ref.watch(databaseProvider),
      assets: rootBundle,
      api: scheduleBaseUrl.isEmpty ? null : ScheduleApi(scheduleBaseUrl),
    ));

// ---------- настройки (shared_preferences) ----------

class Settings {
  const Settings({
    this.profile,
    this.themeMode = ThemeMode.system,
    this.forcedWeek,
    this.notifyBeforeMin = 10,
    this.eveningHomeworkReminder = true,
    this.useDynamicColor = false,
    this.palette = AppPalette.ocean,
    this.amoled = false,
    this.customSubjects = true,
    this.showGroupData = true,
    this.role = UserRole.student,
    this.teacherName,
  });

  final UserProfile? profile; // null — первый запуск, профиль ещё не выбран
  final ThemeMode themeMode;
  final int? forcedWeek; // null — неделя считается автоматически
  final int notifyBeforeMin; // 0 — уведомления перед парой выключены
  final bool eveningHomeworkReminder;
  final bool useDynamicColor; // цвета из обоев (Material You) вместо фирменных
  final AppPalette palette; // цветовая тема
  final bool amoled; // чёрный фон в тёмной теме
  final bool customSubjects; // показывать свои названия и цвета предметов
  final bool showGroupData; // показывать правки и ДЗ старосты
  final UserRole role; // кто пользуется: студент или преподаватель
  final String? teacherName; // как преподаватель записан в списке (полное ФИО или с инициалами)

  /// Режим преподавателя включён и имя выбрано.
  bool get isTeacher => role == UserRole.teacher && teacherName != null;

  /// Нужен ли первый экран выбора (кто вы / какая группа / какой преподаватель).
  bool get needsOnboarding => role == UserRole.teacher ? teacherName == null : profile == null;
}

class SettingsNotifier extends Notifier<Settings> {
  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  @override
  Settings build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final groupId = prefs.getString('groupId');
    return Settings(
      profile: groupId == null
          ? null
          : UserProfile(
              formCode: prefs.getString('form') ?? '',
              groupId: groupId,
              subgroup: prefs.getInt('subgroup') ?? 1,
              pe: PeChoice.parse(prefs.getString('pe')),
            ),
      themeMode: ThemeMode.values.byName(prefs.getString('theme') ?? 'system'),
      forcedWeek: prefs.getInt('forcedWeek'),
      notifyBeforeMin: prefs.getInt('notifyBeforeMin') ?? 10,
      eveningHomeworkReminder: prefs.getBool('eveningHomeworkReminder') ?? true,
      useDynamicColor: prefs.getBool('useDynamicColor') ?? false,
      palette: AppPalette.parse(prefs.getString('palette')),
      amoled: prefs.getBool('amoled') ?? false,
      customSubjects: prefs.getBool('customSubjects') ?? true,
      showGroupData: prefs.getBool('showGroupData') ?? true,
      role: prefs.getString('role') == 'teacher' ? UserRole.teacher : UserRole.student,
      teacherName: prefs.getString('teacherName'),
    );
  }

  Future<void> setProfile(UserProfile profile) async {
    await _prefs.setString('form', profile.formCode);
    await _prefs.setString('groupId', profile.groupId);
    await _prefs.setInt('subgroup', profile.subgroup);
    await _prefs.setString('pe', profile.pe.name);
    ref.invalidateSelf();
  }

  /// Переключает режим. Профиль студента и имя преподавателя хранятся отдельно и не стираются.
  Future<void> setRole(UserRole role) async {
    await _prefs.setString('role', role.name);
    ref.invalidateSelf();
  }

  /// Выбрать себя в списке преподавателей (и сразу включить режим преподавателя).
  Future<void> setTeacher(String name) async {
    await _prefs.setString('teacherName', name);
    await _prefs.setString('role', UserRole.teacher.name);
    ref.invalidateSelf();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    await _prefs.setString('theme', mode.name);
    ref.invalidateSelf();
  }

  Future<void> setForcedWeek(int? week) async {
    if (week == null) {
      await _prefs.remove('forcedWeek');
    } else {
      await _prefs.setInt('forcedWeek', week);
    }
    ref.invalidateSelf();
  }

  Future<void> setNotifyBeforeMin(int minutes) async {
    await _prefs.setInt('notifyBeforeMin', minutes);
    ref.invalidateSelf();
  }

  Future<void> setPalette(AppPalette palette) async {
    await _prefs.setString('palette', palette.id);
    ref.invalidateSelf();
  }

  Future<void> setShowGroupData(bool value) async {
    await _prefs.setBool('showGroupData', value);
    ref.invalidateSelf();
  }

  Future<void> setCustomSubjects(bool value) async {
    await _prefs.setBool('customSubjects', value);
    ref.invalidateSelf();
  }

  Future<void> setAmoled(bool value) async {
    await _prefs.setBool('amoled', value);
    ref.invalidateSelf();
  }

  Future<void> setUseDynamicColor(bool value) async {
    await _prefs.setBool('useDynamicColor', value);
    ref.invalidateSelf();
  }

  Future<void> setEveningHomeworkReminder(bool value) async {
    await _prefs.setBool('eveningHomeworkReminder', value);
    ref.invalidateSelf();
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, Settings>(SettingsNotifier.new);

// ---------- расписание ----------

final indexProvider = FutureProvider<ScheduleIndex>((ref) => ref.watch(repositoryProvider).loadIndex());

final groupScheduleProvider = FutureProvider.family<GroupSchedule, String>(
  (ref, groupId) async {
    await ref.watch(indexProvider.future); // при обновлении списка групп перечитываем и группу
    return ref.watch(repositoryProvider).loadGroup(groupId);
  },
);

/// Всё, что нужно экранам для «моего» расписания.
class MySchedule {
  const MySchedule({
    required this.index,
    required this.schedule,
    required this.profile,
    this.forcedWeek,
    this.overrides = const [],
  });
  final ScheduleIndex index;
  final GroupSchedule schedule;
  final UserProfile profile;
  final int? forcedWeek;
  final List<Override> overrides; // личные правки

  /// Номер недели для даты (с учётом ручного переключателя).
  int weekFor(DateTime day) => forcedWeek ?? weekNumber(day, index.weekAnchor);
}

final myScheduleProvider = FutureProvider<MySchedule?>((ref) async {
  final settings = ref.watch(settingsProvider);
  // Преподаватель: расписание собирается из пар во всех группах; правки студента и данные группы не используются
  if (settings.isTeacher) {
    final index = await ref.watch(indexProvider.future);
    final view = await ref.watch(teacherViewProvider.future);
    if (view == null) return null;
    return MySchedule(index: index, schedule: view.schedule, profile: teacherProfile, forcedWeek: settings.forcedWeek);
  }
  final profile = settings.profile;
  if (profile == null) return null;
  final index = await ref.watch(indexProvider.future);
  final schedule = await ref.watch(groupScheduleProvider(profile.groupId).future);
  final personal = await ref.watch(overridesProvider.future);
  // Правки старосты (для всей группы): только к текущему расписанию группы — после загрузки нового xlsx они сами исчезают
  final group = settings.showGroupData ? await ref.watch(groupSharedProvider.future) : GroupSharedState.empty;
  final groupHash = index.findGroup(profile.groupId)?.hash;
  final overrides = [for (final o in group.activeOverrides(groupHash)) o.toOverride(), ...personal];
  return MySchedule(index: index, schedule: schedule, profile: profile, forcedWeek: settings.forcedWeek, overrides: overrides);
});

// ---------- «сейчас» ----------

/// Текущее время, обновляется раз в 15 секунд — чтобы «до конца пары» и прогресс шли сами.
final nowProvider = StreamProvider<DateTime>((ref) {
  final clock = ref.watch(clockProvider);
  final controller = StreamController<DateTime>();
  controller.add(clock.now());
  final timer = Timer.periodic(const Duration(seconds: 15), (_) => controller.add(clock.now()));
  ref.onDispose(() {
    timer.cancel();
    controller.close();
  });
  return controller.stream;
});

/// Сегодняшний день по Москве.
final todayProvider = Provider<DateTime>((ref) {
  final now = ref.watch(nowProvider).value ?? ref.watch(clockProvider).now();
  return moscowToday(now);
});

// ---------- синхронизация ----------

/// Когда последний раз расписание пришло из сети (для тихой метки «обновлено 2 дня назад»).
final lastFetchedProvider = FutureProvider<DateTime?>((ref) => ref.watch(repositoryProvider).lastFetchedAt());

/// Проверить обновления на сайте и, если что-то изменилось, перечитать расписание.
Future<SyncResult> syncSchedule(ProviderContainer ref) async {
  final repo = ref.read(repositoryProvider);
  final settings = ref.read(settingsProvider);
  final groupId = settings.isTeacher ? null : settings.profile?.groupId;
  final result = await repo.sync(groupId: groupId);
  if (result.indexChanged || result.groupChanged) {
    ref.invalidate(indexProvider);
  }
  final profile = settings.isTeacher ? null : settings.profile;
  if (result.groupChanged && result.diffJson != null && profile != null) {
    final items = summarizeDiff(result.diffJson!, profile);
    if (items.isNotEmpty) {
      ref.read(updateBannerProvider.notifier).show(items);
      // То же — уведомлением (если приложение свёрнуто). Ошибка уведомления не должна ломать синхронизацию
      try {
        await ref.read(notificationGatewayProvider).showNow(
              id: 1,
              title: diffHeadline(items.length),
              body: items.take(3).join('\n'),
            );
      } catch (_) {}
    }
  }
  ref.invalidate(lastFetchedProvider);
  return result;
}

// ---------- домашние задания ----------

/// Файлы вложений к ДЗ (в тестах подменяется).
final attachmentStoreProvider = Provider<AttachmentStore>((ref) => createAttachmentStore(ref.watch(databaseProvider)));

/// Окна выбора файлов и камеры (в тестах подменяется).
final attachmentPickerProvider = Provider<AttachmentPicker>((ref) => createAttachmentPicker());

final homeworkRepositoryProvider =
    Provider<HomeworkRepository>((ref) => HomeworkRepository(ref.watch(databaseProvider), ref.watch(attachmentStoreProvider)));

/// Все ДЗ. После любого изменения вызываем ref.invalidate(homeworkProvider).
final homeworkProvider = FutureProvider<List<HomeworkItem>>((ref) => ref.watch(homeworkRepositoryProvider).all());

// ---------- поиск по институту ----------

/// Расписания всех групп (для поиска). Перечитываются, когда обновился список групп.
final allGroupsProvider = FutureProvider<List<GroupSchedule>>((ref) async {
  await ref.watch(indexProvider.future);
  return ref.watch(repositoryProvider).loadAllGroups();
});

// ---------- баннер «Расписание обновилось» ----------

/// Список изменений, который показывается на экране «Сегодня», пока пользователь не нажмёт «Понятно».
class UpdateBannerNotifier extends Notifier<List<String>> {
  static const _key = 'updateBanner';

  @override
  List<String> build() => ref.watch(sharedPreferencesProvider).getStringList(_key) ?? const [];

  Future<void> show(List<String> items) async {
    await ref.read(sharedPreferencesProvider).setStringList(_key, items);
    state = items;
  }

  Future<void> dismiss() async {
    await ref.read(sharedPreferencesProvider).remove(_key);
    state = const [];
  }
}

final updateBannerProvider = NotifierProvider<UpdateBannerNotifier, List<String>>(UpdateBannerNotifier.new);

// ---------- мост с Android (виджеты, ссылки) ----------

final widgetBridgeProvider = Provider<WidgetBridge>((ref) => const WidgetBridge());
final linkChannelProvider = Provider<LinkChannel>((ref) => LinkChannel());

/// День, который нужно показать на экране «Сегодня» (после нажатия на уведомление). Экран сам его забирает.
class RequestedDayNotifier extends Notifier<DateTime?> {
  @override
  DateTime? build() => null;
  void request(DateTime day) => state = day;
  void clear() => state = null;
}

final requestedDayProvider = NotifierProvider<RequestedDayNotifier, DateTime?>(RequestedDayNotifier.new);

// ---------- свои названия и цвета предметов ----------

final subjectStylesRepositoryProvider = Provider<SubjectStylesRepository>((ref) => SubjectStylesRepository(ref.watch(databaseProvider)));

/// Сохранённые настройки предметов. После изменения вызываем ref.invalidate(subjectStyleMapProvider).
final subjectStyleMapProvider = FutureProvider<Map<String, SubjectStyle>>((ref) => ref.watch(subjectStylesRepositoryProvider).all());

/// То, чем пользуются экраны: настройки + выключатель из «Настройки → Предметы».
final subjectStylesProvider = Provider<SubjectStyles>((ref) {
  final enabled = ref.watch(settingsProvider.select((s) => s.customSubjects));
  final map = ref.watch(subjectStyleMapProvider).value ?? const {};
  return SubjectStyles(enabled: enabled, styles: map);
});

// ---------- общие данные группы (староста) ----------

/// Клиент общего сервера; null — сервер не настроен (функции старосты скрыты).
final sharedApiProvider = Provider<SharedApi?>((ref) => sharedApiUrl.isEmpty ? null : SharedApi(sharedApiUrl, sharedApiKey));

/// Файлы и фото к ДЗ старосты (загрузка и скачивание); null — сервер не настроен.
final groupFilesProvider = Provider<GroupFiles?>((ref) {
  final api = ref.watch(sharedApiProvider);
  return api == null
      ? null
      : GroupFiles(api: api, store: ref.watch(attachmentStoreProvider), prefs: ref.watch(sharedPreferencesProvider));
});

final groupSharedRepositoryProvider = Provider<GroupSharedRepository?>((ref) {
  final api = ref.watch(sharedApiProvider);
  return api == null ? null : GroupSharedRepository(ref.watch(databaseProvider), api);
});

/// Правки и ДЗ старосты для моей группы (из кэша телефона). После обновления с сервера — ref.invalidate(groupSharedProvider).
final groupSharedProvider = FutureProvider<GroupSharedState>((ref) async {
  final groupId = ref.watch(settingsProvider.select((s) => s.isTeacher ? null : s.profile?.groupId));
  final repo = ref.watch(groupSharedRepositoryProvider);
  if (groupId == null || repo == null) return GroupSharedState.empty;
  return repo.cached(groupId);
});

/// Староста ли этот телефон: токен и группа хранятся в настройках телефона.
class EditorNotifier extends Notifier<EditorSession?> {
  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  @override
  EditorSession? build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final token = prefs.getString('editorToken');
    final group = prefs.getString('editorGroup');
    return token == null || group == null ? null : EditorSession(token: token, groupId: group);
  }

  Future<void> set(EditorSession session) async {
    await _prefs.setString('editorToken', session.token);
    await _prefs.setString('editorGroup', session.groupId);
    state = session;
  }

  Future<void> clear() async {
    await _prefs.remove('editorToken');
    await _prefs.remove('editorGroup');
    state = null;
  }
}

final editorProvider = NotifierProvider<EditorNotifier, EditorSession?>(EditorNotifier.new);

/// Староста этой группы (его права действуют, только если он смотрит расписание той же группы).
final isGroupEditorProvider = Provider<bool>((ref) {
  final editor = ref.watch(editorProvider);
  final groupId = ref.watch(settingsProvider.select((s) => s.isTeacher ? null : s.profile?.groupId));
  return editor != null && editor.groupId == groupId && ref.watch(sharedApiProvider) != null;
});

/// Какие ДЗ старосты студент уже отметил выполненными (хранится только у него).
class GroupHomeworkDoneNotifier extends Notifier<Set<String>> {
  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  @override
  Set<String> build() => (ref.watch(sharedPreferencesProvider).getStringList('groupHomeworkDone') ?? const []).toSet();

  Future<void> toggle(String id) async {
    final next = {...state};
    next.contains(id) ? next.remove(id) : next.add(id);
    await _prefs.setStringList('groupHomeworkDone', next.toList());
    state = next;
  }
}

final groupHomeworkDoneProvider = NotifierProvider<GroupHomeworkDoneNotifier, Set<String>>(GroupHomeworkDoneNotifier.new);

/// Все ДЗ старосты группы (с учётом выключателя в настройках), по срокам. Включая ДЗ чужих подгрупп — их видит староста.
final groupHomeworkAllProvider = Provider<List<GroupHomeworkRow>>((ref) {
  if (!ref.watch(settingsProvider.select((s) => s.showGroupData))) return const [];
  return ref.watch(groupSharedProvider).value?.homeworkList ?? const [];
});

/// ДЗ старосты, видимое студенту: для всей группы и для его подгруппы (ДЗ другой подгруппы скрыто).
final groupHomeworkProvider = Provider<List<GroupHomeworkRow>>((ref) {
  final mine = ref.watch(settingsProvider.select((s) => s.profile?.subgroup));
  final all = ref.watch(groupHomeworkAllProvider);
  return mine == null ? all : [for (final h in all) if (h.visibleTo(mine)) h];
});

/// Все невыполненные ДЗ вместе: личные и ДЗ старосты (для виджетов, уведомлений и значков на парах).
/// Выполнено ли ДЗ старосты, студент решает сам (хранится только у него).
final homeworkWithGroupProvider = FutureProvider<List<HomeworkItem>>((ref) async {
  // Преподавателю личные ДЗ студента не показываем (ни на виджетах, ни в напоминаниях)
  if (ref.watch(isTeacherModeProvider)) return const [];
  final personal = await ref.watch(homeworkProvider.future);
  final group = [...ref.watch(groupHomeworkProvider), ...ref.watch(teacherHomeworkProvider)];
  final done = ref.watch(groupHomeworkDoneProvider);
  return [
    ...personal,
    for (final g in group)
      HomeworkItem(subject: g.subject, text: g.text, dueDate: g.dueDate, kind: g.kind, done: done.contains(g.id), createdAt: g.dueDate),
  ];
});

/// ДЗ преподавателей, видимое студенту: для всей группы и для его подгруппы.
final teacherHomeworkProvider = Provider<List<GroupHomeworkRow>>((ref) {
  if (!ref.watch(settingsProvider.select((s) => s.showGroupData))) return const [];
  final mine = ref.watch(settingsProvider.select((s) => s.profile?.subgroup));
  final all = ref.watch(groupSharedProvider).value?.teacherHomeworkList ?? const <GroupHomeworkRow>[];
  return mine == null ? all : [for (final h in all) if (h.visibleTo(mine)) h];
});

/// Что нового пришло с сервера: ДЗ старосты и ДЗ преподавателей (для уведомлений).
class GroupNews {
  const GroupNews({this.homework = const [], this.teacherHomework = const [], this.assessments = const []});
  final List<GroupHomeworkRow> homework;
  final List<GroupHomeworkRow> teacherHomework;

  /// Аттестации, зачёты и экзамены, которые объявил староста.
  final List<GroupOverrideRow> assessments;
  bool get isEmpty => homework.isEmpty && teacherHomework.isEmpty && assessments.isEmpty;
  static const none = GroupNews();
}

/// Обновить общие данные группы с сервера. Ошибки связи молча игнорируются (остаётся кэш).
/// Возвращает ДЗ, которых раньше не было (для уведомления). В режиме преподавателя данных группы нет.
Future<GroupNews> syncGroupShared(ProviderContainer c) async {
  final repo = c.read(groupSharedRepositoryProvider);
  final settings = c.read(settingsProvider);
  final groupId = settings.isTeacher ? null : settings.profile?.groupId;
  if (repo == null || groupId == null) return GroupNews.none;
  try {
    final result = await repo.sync(groupId);
    // Староста стирает с сервера правки к устаревшему расписанию (новое расписание точнее)
    final editor = c.read(editorProvider);
    final hash = (await c.read(indexProvider.future)).findGroup(groupId)?.hash;
    final api = c.read(sharedApiProvider);
    if (editor != null && editor.groupId == groupId && hash != null && api != null && result.state.staleOverrides(hash).isNotEmpty) {
      try {
        await api.clearStale(editor.token, hash);
        await repo.sync(groupId);
      } on SharedApiException {
        // повторим в следующий раз
      }
    }
    c.invalidate(groupSharedProvider);
    // Сервер убирает ДЗ через 3 недели после срока сдачи: скачанные файлы исчезнувших ДЗ стираем из памяти телефона
    try {
      await c.read(groupFilesProvider)?.forgetExcept(result.state.fileIds);
    } catch (_) {}
    // Уведомление только о ДЗ, которое относится ко мне (общее или для моей подгруппы)
    final mine = settings.profile?.subgroup;
    bool visible(GroupHomeworkRow h) => mine == null || h.visibleTo(mine);
    return GroupNews(
      homework: [for (final h in result.newHomework) if (visible(h)) h],
      teacherHomework: [for (final h in result.newTeacherHomework) if (visible(h)) h],
      assessments: result.newAssessments,
    );
  } on SharedApiException {
    return GroupNews.none;
  }
}

// ---------- режим преподавателя ----------

/// Включён ли режим преподавателя (и выбрано имя).
final isTeacherModeProvider = Provider<bool>((ref) => ref.watch(settingsProvider.select((s) => s.isTeacher)));

/// Расписание и адресаты ДЗ выбранного преподавателя (собираются из файлов всех групп). null — режим выключен.
final teacherViewProvider = FutureProvider<TeacherView?>((ref) async {
  final name = ref.watch(settingsProvider.select((s) => s.isTeacher ? s.teacherName : null));
  if (name == null) return null;
  final schedules = await ref.watch(allGroupsProvider.future);
  return buildTeacherView(name, schedules);
});

/// Код преподавателя на этом телефоне: токен, имя из кода и разрешённые группы (хранится в настройках телефона).
class TeacherSessionNotifier extends Notifier<TeacherSession?> {
  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  @override
  TeacherSession? build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final token = prefs.getString('teacherToken');
    final name = prefs.getString('teacherCodeName');
    if (token == null || name == null) return null;
    return TeacherSession(token: token, teacher: name, groups: prefs.getStringList('teacherCodeGroups') ?? const []);
  }

  Future<void> set(TeacherSession session) async {
    await _prefs.setString('teacherToken', session.token);
    await _prefs.setString('teacherCodeName', session.teacher);
    await _prefs.setStringList('teacherCodeGroups', session.groups);
    state = session;
  }

  Future<void> clear() async {
    await _prefs.remove('teacherToken');
    await _prefs.remove('teacherCodeName');
    await _prefs.remove('teacherCodeGroups');
    await _prefs.remove('teacherSentCache');
    state = null;
  }
}

final teacherSessionProvider = NotifierProvider<TeacherSessionNotifier, TeacherSession?>(TeacherSessionNotifier.new);

/// Сколько ждать сервер, если у преподавателя уже есть сохранённый список (в тестах подменяется).
final teacherSentWaitProvider = Provider<Duration>((ref) => const Duration(seconds: 4));

/// Что преподаватель уже отправил студентам (с сервера; без связи показывается последняя сохранённая копия).
/// Если копия есть, а сервер отвечает медленно (больше [teacherSentWaitProvider]) или с ошибкой, сразу показываем копию:
/// иначе на слабой сети вкладка до 15 секунд крутила бы кружок. Исключение — «Доступ отозван»: тогда копию не показываем.
/// После изменения вызываем ref.invalidate(teacherSentProvider).
/// Автоповтор Riverpod здесь выключен: по умолчанию он повторял бы запрос до 10 раз (около 40 секунд), и вместо
/// ошибки («Доступ отозван», «Нет связи») человек всё это время видел бы крутящийся кружок. Повторить можно кнопкой.
final teacherSentProvider = FutureProvider<List<TeacherHomeworkBatch>>((ref) async {
  final session = ref.watch(teacherSessionProvider);
  final api = ref.watch(sharedApiProvider);
  if (session == null || api == null) return const [];
  final prefs = ref.read(sharedPreferencesProvider);
  final wait = ref.read(teacherSentWaitProvider);

  List<TeacherHomeworkBatch>? cached;
  try {
    final saved = jsonDecode(prefs.getString('teacherSentCache') ?? 'null');
    if (saved is List) cached = [for (final b in saved) TeacherHomeworkBatch.fromJson(b as Map<String, dynamic>)];
  } catch (_) {}

  Future<List<TeacherHomeworkBatch>> saveAfter(Future<List<TeacherHomeworkBatch>> request) async {
    final list = await request;
    await prefs.setString('teacherSentCache', jsonEncode([for (final b in list) b.toJson()]));
    return list;
  }

  final request = saveAfter(api.getTeacherHomework(session.token));
  try {
    return cached == null ? await request : await request.timeout(wait);
  } on TimeoutException {
    // Ответ ещё придёт и сам обновит сохранённую копию (для следующего открытия); ошибку позднего ответа гасим
    unawaited(request.then<void>((_) {}, onError: (Object _) {}));
    return cached!;
  } on SharedApiException catch (e) {
    if (cached != null && e.code != 'bad_token') return cached;
    rethrow;
  }
}, retry: (retryCount, error) => null);

// ---------- личные правки ----------

final overridesRepositoryProvider = Provider<OverridesRepository>((ref) => OverridesRepository(ref.watch(databaseProvider)));

/// Все личные правки. После изменения вызываем ref.invalidate(overridesProvider).
final overridesProvider = FutureProvider<List<Override>>((ref) => ref.watch(overridesRepositoryProvider).all());

// ---------- уведомления ----------

final notificationGatewayProvider = Provider<NotificationGateway>((ref) => kIsWeb ? NoopNotificationGateway() : LocalNotificationGateway());


// ---------- виджеты: добавление одним нажатием ----------

final widgetPinnerProvider = Provider<WidgetPinner>((ref) => HomeWidgetPinner());

/// Умеет ли этот телефон добавлять виджет по кнопке (на нём же и показываем подсказку).
final widgetPinSupportedProvider = FutureProvider<bool>((ref) => ref.watch(widgetPinnerProvider).isSupported());

/// Показывать ли на «Сегодня» подсказку «Добавьте виджет»: пока человек её не закрыл и не добавил виджет.
class WidgetPromoNotifier extends Notifier<bool> {
  static const _key = 'widgetPromoDismissed';

  @override
  bool build() => !(ref.watch(sharedPreferencesProvider).getBool(_key) ?? false);

  Future<void> dismiss() async {
    await ref.read(sharedPreferencesProvider).setBool(_key, true);
    state = false;
  }
}

final widgetPromoProvider = NotifierProvider<WidgetPromoNotifier, bool>(WidgetPromoNotifier.new);
