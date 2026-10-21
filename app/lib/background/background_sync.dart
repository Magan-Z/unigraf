// Фоновая проверка обновлений раз в ~6 часов (АРХИТЕКТУРА.md, §7.5).
// Работает, даже если приложение закрыто: качает свежее расписание, показывает «Расписание обновилось»,
// пересобирает снимок для виджетов и заново ставит уведомления на 7 дней вперёд.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../app_outputs.dart';
import '../app_state.dart';
import '../config.dart';
import '../core/formatting.dart';
import '../domain/assessments.dart';

const _uniqueName = 'unigraf-background-sync';
const _taskName = 'syncSchedule';

/// Сама работа — отдельной функцией, чтобы её можно было проверить тестом.
Future<void> runBackgroundSync(ProviderContainer container) async {
  await syncSchedule(container);
  // Правки и ДЗ старосты и преподавателей. Если появилось новое ДЗ, сообщаем уведомлением (приложение может быть закрыто)
  final fresh = await syncGroupShared(container);
  if (!fresh.isEmpty && container.read(settingsProvider).showGroupData) {
    final gateway = container.read(notificationGatewayProvider);
    try {
      if (fresh.homework.isNotEmpty) {
        await gateway.showNow(
          id: 2,
          title: fresh.homework.length == 1 ? 'Староста добавил ДЗ' : 'Староста добавил ДЗ: ${fresh.homework.length}',
          body: fresh.homework.take(3).map((h) => '${h.subject}: ${h.text}').join('\n'),
        );
      }
      if (fresh.teacherHomework.isNotEmpty) {
        await gateway.showNow(
          id: 3,
          title: fresh.teacherHomework.length == 1 ? 'Преподаватель добавил ДЗ' : 'Преподаватели добавили ДЗ: ${fresh.teacherHomework.length}',
          body: fresh.teacherHomework.take(3).map((h) => '${h.subject}${h.author == null ? '' : ' (${h.author})'}: ${h.text}').join('\n'),
        );
      }
      if (fresh.assessments.isNotEmpty) {
        final list = fresh.assessments;
        await gateway.showNow(
          id: 4,
          title: list.length == 1 ? 'Староста объявил: ${list.first.kind!.title.toLowerCase()}' : 'Староста сделал объявления: ${list.length}',
          body: list.take(3).map((o) {
            final note = visibleNote(o.kind!, o.note);
            return '${o.subject ?? o.matchSubject ?? 'Пара'} · ${dayTitle(o.date)}, ${o.pair} пара${note == null ? '' : ' · $note'}';
          }).join('\n'),
        );
      }
    } catch (_) {}
  }
  await refreshOutputs(container);
}

/// Точка входа для WorkManager: запускается в отдельном «фоновом» окружении Flutter.
@pragma('vm:entry-point')
void backgroundCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
    try {
      await runBackgroundSync(container);
      return true;
    } catch (_) {
      return false; // WorkManager повторит попытку позже
    } finally {
      container.dispose();
    }
  });
}

/// Регистрирует периодическую задачу. Повторный вызов ничего не меняет (policy keep).
Future<void> registerBackgroundSync() async {
  try {
    await Workmanager().initialize(backgroundCallbackDispatcher);
    await Workmanager().registerPeriodicTask(
      _uniqueName,
      _taskName,
      frequency: const Duration(hours: backgroundSyncHours),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
  } catch (_) {
    // Нет фоновых задач (тесты, не Android) — приложение работает и без них
  }
}
