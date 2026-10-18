// Анонимный счётчик пользователей: не чаще раза в сутки приложение сообщает серверу случайный номер установки,
// платформу и версию. Имени, группы, расписания и адреса устройства в запросе нет. Номер создаётся при первом запуске
// и лежит только в настройках телефона (при переустановке будет новый).
//
// Счётчик никогда не мешает работе: запрос уходит в фоне через несколько секунд после запуска, а любая ошибка
// (нет сети, сервер недоступен) молча игнорируется — завтра попробуем снова.

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:shared_preferences/shared_preferences.dart';

import 'data/remote/shared_api.dart';

/// Версия приложения; подставляется при сборке (--dart-define=APP_VERSION=0.3.4). В локальной сборке пустая.
const appVersion = String.fromEnvironment('APP_VERSION', defaultValue: '');

const _installKey = 'usage.install_id';
const _lastDayKey = 'usage.last_day';

/// Платформа для статистики: android, ios, web или other.
String usagePlatform() {
  if (kIsWeb) return 'web';
  return switch (defaultTargetPlatform) {
    TargetPlatform.android => 'android',
    TargetPlatform.iOS => 'ios',
    _ => 'other',
  };
}

String _newInstallId(Random random) => List.generate(32, (_) => random.nextInt(16).toRadixString(16)).join();

bool _sending = false;

/// Отправляет отметку «сегодня пользовался», если сегодня ещё не отправляли. Ничего не бросает.
Future<void> sendUsagePing({
  required SharedPreferences prefs,
  required SharedApi? api,
  required DateTime now,
  String? platform,
  String? version,
  Random? random,
  Uri? location,
}) async {
  if (api == null || _sending) return;
  // Проверочный режим для разработчика: адрес вида .../app/?nocount не засоряет счётчик тестовыми отметками
  if ((location ?? (kIsWeb ? Uri.base : null))?.queryParameters.containsKey('nocount') ?? false) return;
  final today = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  if (prefs.getString(_lastDayKey) == today) return;
  _sending = true;
  try {
    var id = prefs.getString(_installKey);
    if (id == null || id.length != 32) {
      id = _newInstallId(random ?? Random.secure());
      await prefs.setString(_installKey, id);
    }
    await api.pingUsage(id, platform ?? usagePlatform(), version ?? appVersion);
    await prefs.setString(_lastDayKey, today);
  } catch (_) {
    // не получилось (нет сети и т. п.) — не страшно, повторим при следующем открытии
  } finally {
    _sending = false;
  }
}
