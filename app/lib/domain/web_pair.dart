// Вход преподавателя на странице «Отправить ДЗ с компьютера»: что лежит в QR-коде и в текстовом коде, список компьютеров.

/// Начало содержимого QR-кода на странице: `unigraf://pair/<номер запроса>`.
const webPairQrPrefix = 'unigraf://pair/';

final _uuid = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$');
// Буквы без похожих на цифры (без I, L, O) и без 0, 1: так выдаёт код сервер
final _textCode = RegExp(r'^[A-HJKMNP-Z2-9]{8}$');

/// Номер запроса входа из QR-кода или null, если это не наш код (чужой QR, обычная ссылка).
String? parsePairQr(String raw) {
  final text = raw.trim().toLowerCase();
  final id = text.startsWith(webPairQrPrefix) ? text.substring(webPairQrPrefix.length) : text;
  return _uuid.hasMatch(id) ? id : null;
}

/// Текстовый код с экрана компьютера («QAG3-V3FY», регистр и дефис неважны) приведён к виду сервера или null, если он неверной формы.
String? parseTextCode(String raw) {
  final text = raw.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');
  return _textCode.hasMatch(text) ? text : null;
}

/// Компьютер, где сейчас выполнен вход (строка списка).
class WebSessionInfo {
  const WebSessionInfo({required this.id, required this.createdAt, required this.lastSeen});

  final String id;
  final DateTime createdAt;
  final DateTime lastSeen;

  factory WebSessionInfo.fromJson(Map<String, dynamic> j) => WebSessionInfo(
        id: j['id'] as String,
        createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
        lastSeen: DateTime.parse(j['last_seen'] as String).toLocal(),
      );
}
