// Анонимный счётчик пользователей: раз в сутки, без лишних данных, молча при сбоях.

import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unigraf/data/remote/shared_api.dart';
import 'package:unigraf/usage_ping.dart';

void main() {
  late SharedPreferences prefs;
  late List<http.Request> sent;
  late SharedApi api;
  var fail = false;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    sent = [];
    fail = false;
    api = SharedApi('https://example.test', 'key', client: MockClient((request) async {
      sent.add(request);
      if (fail) throw http.ClientException('нет сети');
      return http.Response('', 204);
    }));
  });

  test('отправляет только номер установки, платформу и версию', () async {
    await sendUsagePing(prefs: prefs, api: api, now: DateTime(2026, 10, 16, 9), platform: 'android', version: '0.3.4', random: Random(1));
    expect(sent, hasLength(1));
    expect(sent.single.url.path, '/rest/v1/rpc/ping_usage');
    final body = jsonDecode(sent.single.body) as Map<String, dynamic>;
    expect(body.keys.toSet(), {'p_install', 'p_platform', 'p_version'});
    expect(body['p_install'], matches(RegExp(r'^[0-9a-f]{32}$')));
    expect(body['p_platform'], 'android');
    expect(body['p_version'], '0.3.4');
  });

  test('в тот же день второй раз не отправляет, на следующий день отправляет с тем же номером', () async {
    await sendUsagePing(prefs: prefs, api: api, now: DateTime(2026, 10, 16, 9), platform: 'web');
    await sendUsagePing(prefs: prefs, api: api, now: DateTime(2026, 10, 16, 22), platform: 'web');
    expect(sent, hasLength(1));
    await sendUsagePing(prefs: prefs, api: api, now: DateTime(2026, 10, 17, 8), platform: 'web');
    expect(sent, hasLength(2));
    expect(jsonDecode(sent[0].body)['p_install'], jsonDecode(sent[1].body)['p_install']);
  });

  test('адрес с ?nocount (проверки разработчика) ничего не отправляет и не запоминает', () async {
    await sendUsagePing(prefs: prefs, api: api, now: DateTime(2026, 10, 16, 9), platform: 'web', location: Uri.parse('https://example.test/app/?nocount'));
    expect(sent, isEmpty);
    expect(prefs.getString('usage.last_day'), isNull);
    expect(prefs.getString('usage.install_id'), isNull);
    // обычный адрес по-прежнему считается
    await sendUsagePing(prefs: prefs, api: api, now: DateTime(2026, 10, 16, 9), platform: 'web', location: Uri.parse('https://example.test/app/?dpr=2'));
    expect(sent, hasLength(1));
  });

  test('без сети молча ничего не делает, а при следующем открытии пробует снова', () async {
    fail = true;
    await sendUsagePing(prefs: prefs, api: api, now: DateTime(2026, 10, 16, 9), platform: 'android');
    expect(prefs.getString('usage.last_day'), isNull);
    fail = false;
    await sendUsagePing(prefs: prefs, api: api, now: DateTime(2026, 10, 16, 9, 5), platform: 'android');
    expect(sent, hasLength(2));
    expect(prefs.getString('usage.last_day'), '2026-10-16');
  });

  test('если сервер не настроен, ничего не отправляется и не падает', () async {
    await sendUsagePing(prefs: prefs, api: null, now: DateTime(2026, 10, 16), platform: 'android');
    expect(sent, isEmpty);
    expect(prefs.getString('usage.install_id'), isNull);
  });
}
