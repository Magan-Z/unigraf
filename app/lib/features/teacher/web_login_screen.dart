// «Вход на компьютере»: преподаватель подтверждает с телефона вход на странице «Отправить ДЗ с компьютера».
// Страница показывает QR, 4-значное число и текстовый код. QR сканируем камерой и вводим число с экрана (защита от чужого QR),
// текстовый код вводим вручную (для веб-версии и телефонов без камеры). Здесь же список компьютеров, где вход ещё открыт.

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
  List<WebSessionInfo>? _sessions;
  String? _sessionsError;
  String? _message; // результат последнего входа
  bool _messageIsError = false;
  bool _busy = false;

  TeacherActions get _actions => TeacherActions(ref.container);

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  @override
  void dispose() {
    _code.dispose();
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
      appBar: AppBar(title: const Text('Вход на компьютере')),
      body: ListView(padding: const EdgeInsets.all(Gap.lg), children: [
        Text('Отправляйте ДЗ студентам с компьютера в аудитории, не перенося файлы на телефон.', style: theme.textTheme.bodyLarge),
        const SizedBox(height: Gap.sm),
        Text('1. Откройте на компьютере страницу:', style: theme.textTheme.bodyMedium),
        const SizedBox(height: Gap.xs),
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
        const SizedBox(height: Gap.xs),
        Text('2. Отсканируйте QR с экрана компьютера и введите число, которое там показано. '
            'Или введите код из 8 знаков.', style: theme.textTheme.bodyMedium),
        const SizedBox(height: Gap.sm),
        Container(
          padding: const EdgeInsets.all(Gap.md),
          decoration: BoxDecoration(color: scheme.secondaryContainer, borderRadius: BorderRadius.circular(Radii.sm)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.shield_outlined, color: scheme.onSecondaryContainer),
            const SizedBox(width: Gap.sm),
            Expanded(
              child: Text('Входите только на компьютере, где страницу открыли вы сами. Никому не пересылайте код и число с экрана.',
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSecondaryContainer)),
            ),
          ]),
        ),
        const SizedBox(height: Gap.lg),
        if (!kIsWeb) ...[
          FilledButton.icon(
            onPressed: _busy ? null : _scan,
            icon: const Icon(Icons.qr_code_scanner_rounded),
            label: const Text('Сканировать QR'),
          ),
          const SizedBox(height: Gap.lg),
        ],
        TextField(
          controller: _code,
          enabled: !_busy,
          textCapitalization: TextCapitalization.characters,
          textInputAction: TextInputAction.done,
          inputFormatters: [LengthLimitingTextInputFormatter(9)],
          onSubmitted: (_) => _submitCode(),
          decoration: const InputDecoration(labelText: 'Код с экрана компьютера', hintText: 'ABCD-EFGH', border: OutlineInputBorder()),
        ),
        const SizedBox(height: Gap.sm),
        OutlinedButton(onPressed: _busy ? null : _submitCode, child: Text(_busy ? 'Проверяем…' : 'Войти по коду')),
        if (_message != null) ...[
          const SizedBox(height: Gap.md),
          Text(_message!, style: theme.textTheme.bodyMedium?.copyWith(color: _messageIsError ? scheme.error : scheme.primary)),
        ],
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

/// Окно ввода числа с экрана компьютера (4 цифры).
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
    return AlertDialog(
      title: const Text('Число с экрана компьютера'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Введите 4 цифры, которые показаны рядом с QR на компьютере. Если там их нет или вы не открывали страницу сами, нажмите «Отмена».'),
        const SizedBox(height: Gap.md),
        TextField(
          controller: _number,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
          textInputAction: TextInputAction.done,
          onChanged: (_) => setState(() {}),
          onSubmitted: (v) => v.length == 4 ? Navigator.of(context).pop(v) : null,
          decoration: const InputDecoration(labelText: 'Число', border: OutlineInputBorder()),
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
      appBar: AppBar(title: const Text('Наведите на QR на компьютере')),
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
