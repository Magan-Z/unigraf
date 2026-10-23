// «Отправить ДЗ с компьютера»: преподаватель подтверждает с телефона вход на странице «Отправить ДЗ с компьютера».
// Страница показывает QR, 4-значное число и текстовый код. QR сканируем камерой и вводим число с экрана (защита от чужого QR),
// текстовый код вводим вручную (для веб-версии и телефонов без камеры). Здесь же список компьютеров, где вход ещё открыт.

import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../config.dart';
import '../../data/remote/shared_api.dart';
import '../../domain/web_pair.dart';
import '../../teacher_actions.dart';
import '../../theme/tokens.dart';

/// Открывает камеру и возвращает считанный код (null — закрыли, не считав). В тестах подменяется.
final qrScanProvider = Provider<Future<String?> Function(BuildContext context)>((ref) => _openScanner);

/// Адрес страницы для компьютера (его преподаватель добавляет в закладки).
String get teacherPageUrl => '${scheduleBaseUrl.endsWith('/') ? scheduleBaseUrl : '$scheduleBaseUrl/'}teacher/';

class WebLoginScreen extends ConsumerStatefulWidget {
  const WebLoginScreen({super.key});

  @override
  ConsumerState<WebLoginScreen> createState() => _WebLoginScreenState();
}

class _WebLoginScreenState extends ConsumerState<WebLoginScreen> {
  final _code = TextEditingController();
  final _codeFocus = FocusNode();
  List<WebSessionInfo>? _sessions;
  String? _sessionsError;
  String? _message; // результат последнего входа
  bool _messageIsError = false;
  bool _busy = false;
  Timer? _refresh;

  TeacherActions get _actions => TeacherActions(ref.container);

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  @override
  void dispose() {
    _refresh?.cancel();
    _code.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  Future<void> _loadSessions() async {
    try {
      final list = await _actions.webSessions();
      if (mounted) setState(() => _sessions = list);
    } on SharedApiException catch (e) {
      if (mounted) setState(() => _sessionsError = e.message);
    }
  }

  void _say(String text, {bool error = false}) => setState(() {
        _message = text;
        _messageIsError = error;
      });

  Future<void> _approve(String ref, {String? number}) async {
    setState(() => _busy = true);
    try {
      await _actions.approveWebLogin(ref, number: number);
      if (!mounted) return;
      _code.clear();
      _say('Готово: на компьютере откроется форма отправки. После отправки ДЗ вход закроется сам.');
      await _loadSessions();
      // компьютер получает вход не сразу (страница спрашивает сервер раз в пару секунд): обновим список ещё раз
      _refresh?.cancel();
      _refresh = Timer(const Duration(seconds: 4), _loadSessions);
    } on SharedApiException catch (e) {
      if (mounted) _say(e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _scan() async {
    final raw = await ref.read(qrScanProvider)(context);
    if (raw == null || !mounted) return;
    final id = parsePairQr(raw);
    if (id == null) {
      _say('Это не код входа UniGraf. Откройте страницу на компьютере и сканируйте QR с неё', error: true);
      return;
    }
    final number = await showDialog<String>(context: context, builder: (_) => const _NumberDialog());
    if (number == null || !mounted) return;
    if (number == _useCodeInstead) {
      _codeFocus.requestFocus();
      return;
    }
    await _approve(id, number: number);
  }

  Future<void> _submitCode() async {
    final code = parseTextCode(_code.text);
    if (code == null) {
      _say('Код состоит из 8 знаков (буквы и цифры), как показано на экране компьютера', error: true);
      return;
    }
    await _approve(code);
  }

  Future<void> _end(WebSessionInfo s) async {
    try {
      await _actions.endWebSession(s.id);
      await _loadSessions();
    } on SharedApiException catch (e) {
      if (mounted) _say(e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('ДЗ с компьютера')),
      body: ListView(padding: const EdgeInsets.all(Gap.lg), children: [
        Text('Файлы лежат на компьютере в аудитории? Отправьте ДЗ оттуда, не перенося их на телефон.', style: theme.textTheme.bodyLarge),
        const SizedBox(height: Gap.lg),
        Text('Откройте на компьютере страницу', style: theme.textTheme.titleMedium),
        const SizedBox(height: Gap.xs),
        if (scheduleBaseUrl.isNotEmpty)
          Row(children: [
            Expanded(child: SelectableText(teacherPageUrl, style: theme.textTheme.bodyMedium?.copyWith(color: scheme.primary))),
            IconButton(
              tooltip: 'Скопировать адрес',
              icon: const Icon(Icons.copy_rounded),
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                await Clipboard.setData(ClipboardData(text: teacherPageUrl));
                messenger.showSnackBar(const SnackBar(content: Text('Адрес скопирован')));
              },
            ),
          ]),
        const SizedBox(height: Gap.lg),
        Text('Войдите одним из двух способов', style: theme.textTheme.titleMedium),
        const SizedBox(height: Gap.sm),
        if (!kIsWeb) ...[
          _MethodCard(
            icon: Icons.qr_code_scanner_rounded,
            title: 'По QR-коду',
            text: 'Наведите камеру на QR на экране компьютера. Потом приложение попросит число из 4 цифр с того же экрана.',
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy ? null : _scan,
                icon: const Icon(Icons.qr_code_scanner_rounded),
                label: const Text('Сканировать QR'),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Gap.sm),
            child: Row(children: [
              const Expanded(child: Divider()),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Gap.md),
                child: Text('или', style: theme.textTheme.labelLarge?.copyWith(color: scheme.onSurfaceVariant)),
              ),
              const Expanded(child: Divider()),
            ]),
          ),
        ],
        _MethodCard(
          icon: Icons.keyboard_alt_outlined,
          title: 'По коду',
          text: 'Код из 8 знаков показан на экране компьютера. Камера и число с экрана не нужны.',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(
              controller: _code,
              focusNode: _codeFocus,
              enabled: !_busy,
              textCapitalization: TextCapitalization.characters,
              textInputAction: TextInputAction.done,
              inputFormatters: [LengthLimitingTextInputFormatter(9)],
              onSubmitted: (_) => _submitCode(),
              decoration: const InputDecoration(labelText: 'Код из 8 знаков', hintText: 'ABCD-EFGH', border: OutlineInputBorder()),
            ),
            const SizedBox(height: Gap.sm),
            FilledButton.tonal(onPressed: _busy ? null : _submitCode, child: Text(_busy ? 'Проверяем…' : 'Войти по коду')),
          ]),
        ),
        if (_message != null) ...[
          const SizedBox(height: Gap.md),
          Text(_message!, style: theme.textTheme.bodyMedium?.copyWith(color: _messageIsError ? scheme.error : scheme.primary)),
        ],
        const SizedBox(height: Gap.lg),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.shield_outlined, size: 20, color: scheme.onSurfaceVariant),
          const SizedBox(width: Gap.sm),
          Expanded(
            child: Text('Входите только на компьютере, где страницу открыли вы сами. Никому не пересылайте код и число с экрана.',
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          ),
        ]),
        const SizedBox(height: Gap.xl),
        Text('Компьютеры, где вход открыт', style: theme.textTheme.titleMedium),
        const SizedBox(height: Gap.sm),
        if (_sessionsError != null)
          Text(_sessionsError!, style: theme.textTheme.bodyMedium?.copyWith(color: scheme.error))
        else if (_sessions == null)
          const Padding(padding: EdgeInsets.all(Gap.md), child: Center(child: CircularProgressIndicator()))
        else if (_sessions!.isEmpty)
          Text('Сейчас нигде. После отправки ДЗ вход закрывается сам.', style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant))
        else
          for (final s in _sessions!)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.computer_rounded),
              title: Text('Вход в ${_clock(s.createdAt)}'),
              subtitle: Text('Последнее действие в ${_clock(s.lastSeen)}'),
              trailing: TextButton(onPressed: () => _end(s), child: const Text('Завершить')),
            ),
      ]),
    );
  }

  String _clock(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

/// Способ входа: значок, название, пояснение и то, что нужно сделать.
class _MethodCard extends StatelessWidget {
  const _MethodCard({required this.icon, required this.title, required this.text, required this.child});
  final IconData icon;
  final String title;
  final String text;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(Gap.lg),
      decoration: BoxDecoration(color: scheme.surfaceContainerLow, borderRadius: BorderRadius.circular(Radii.lg)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(Radii.sm)),
            child: Icon(icon, color: scheme.onPrimaryContainer),
          ),
          const SizedBox(width: Gap.md),
          Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
        ]),
        const SizedBox(height: Gap.md),
        Text(text, style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
        const SizedBox(height: Gap.md),
        child,
      ]),
    );
  }
}

/// Результат окна числа, когда вместо числа нужно ввести код из 8 знаков.
const _useCodeInstead = 'use-code';

/// Окно ввода числа с экрана компьютера (4 цифры). Число и код из 8 знаков разные: окно прямо об этом говорит.
class _NumberDialog extends StatefulWidget {
  const _NumberDialog();

  @override
  State<_NumberDialog> createState() => _NumberDialogState();
}

class _NumberDialogState extends State<_NumberDialog> {
  final _number = TextEditingController();

  @override
  void dispose() {
    _number.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Введите число с экрана'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('4 цифры под QR-кодом на компьютере. Это не код из 8 знаков. Если вы сами не открывали страницу, нажмите «Отмена».'),
        const SizedBox(height: Gap.md),
        TextField(
          controller: _number,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
          textInputAction: TextInputAction.done,
          onChanged: (_) => setState(() {}),
          onSubmitted: (v) => v.length == 4 ? Navigator.of(context).pop(v) : null,
          decoration: const InputDecoration(labelText: 'Число из 4 цифр', border: OutlineInputBorder()),
        ),
        const SizedBox(height: Gap.sm),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_useCodeInstead),
          child: Text('Лучше ввести код из 8 знаков', style: theme.textTheme.labelLarge),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Отмена')),
        FilledButton(onPressed: _number.text.length == 4 ? () => Navigator.of(context).pop(_number.text) : null, child: const Text('Войти')),
      ],
    );
  }
}

Future<String?> _openScanner(BuildContext context) => Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const _ScannerPage()));

class _ScannerPage extends StatefulWidget {
  const _ScannerPage();

  @override
  State<_ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<_ScannerPage> {
  final _controller = MobileScannerController(formats: const [BarcodeFormat.qrCode], detectionSpeed: DetectionSpeed.noDuplicates);
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final b in capture.barcodes) {
      final raw = b.rawValue;
      if (raw != null && raw.isNotEmpty) {
        _done = true;
        Navigator.of(context).pop(raw);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Сканируйте QR')),
      body: MobileScanner(
        controller: _controller,
        onDetect: _onDetect,
        errorBuilder: (context, error) => Center(
          child: Padding(
            padding: const EdgeInsets.all(Gap.xl),
            child: Text(
              error.errorCode == MobileScannerErrorCode.permissionDenied
                  ? 'Нет доступа к камере. Разрешите камеру в настройках телефона или введите код с экрана компьютера вручную.'
                  : 'Камера не запустилась. Введите код с экрана компьютера вручную.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
