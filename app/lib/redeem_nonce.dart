// Метка ввода кода (nonce), которая переживает обрыв связи и перезапуск приложения.
// Сервер гасит код сразу; если ответ с токеном потерялся, повторный ввод того же кода с той же меткой вернёт тот же токен.

import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import 'data/remote/shared_api.dart';

/// Вызывает [call] с меткой для этого кода. Метка хранится в телефоне, пока ввод не завершится:
/// при обрыве связи или ошибке сервера остаётся (повтор того же кода использует её же), при успехе и при окончательном
/// отказе («код не подошёл», «уже использован») стирается. [kind] — 'editor' или 'teacher' (у каждого своя метка).
Future<T> redeemWithNonce<T>({
  required SharedPreferences prefs,
  required String kind,
  required String code,
  required Future<T> Function(String nonce) call,
  Random? random,
}) async {
  final key = 'redeemNonce.$kind';
  final normalized = code.trim().toUpperCase();
  final saved = prefs.getString(key);
  final sep = saved?.indexOf('|') ?? -1;
  var nonce = saved != null && sep > 0 && saved.substring(0, sep) == normalized ? saved.substring(sep + 1) : null;
  if (nonce == null) {
    nonce = newRedeemNonce(random);
    await prefs.setString(key, '$normalized|$nonce');
  }
  try {
    final result = await call(nonce);
    await prefs.remove(key);
    return result;
  } on SharedApiException catch (e) {
    if (e.code == 'bad_code' || e.code == 'code_used') await prefs.remove(key);
    rethrow;
  }
}
