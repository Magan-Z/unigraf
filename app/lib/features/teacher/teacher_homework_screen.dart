// Вкладка «ДЗ» в режиме преподавателя: «Домашка студентам». Без кода — приглашение ввести код;
// с кодом — список отправленного (кому, срок, файлы; изменить и удалить), кнопка «Отправить ДЗ» и вход для отправки с компьютера.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_state.dart';
import '../../core/formatting.dart';
import '../../data/remote/shared_api.dart';
import '../../domain/search.dart';
import '../../domain/teacher_homework.dart';
import '../../teacher_actions.dart';
import '../../theme/tokens.dart';
import '../common/empty_state.dart';
import '../common/illustrations.dart';
import '../common/reveal.dart';
import '../common/word_fit_text.dart';
import '../homework/attachment_widgets.dart';
import 'teacher_code_dialog.dart';
import 'teacher_homework_sheet.dart';
import 'web_login_screen.dart';

class TeacherHomeworkScreen extends ConsumerWidget {
  const TeacherHomeworkScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(teacherSessionProvider);
    final serverOn = ref.watch(sharedApiProvider) != null;

    if (session == null || !serverOn) {
      return EmptyState(
        illustration: IllustrationKind.groupHomework,
        title: 'Домашка студентам',
        subtitle: serverOn
            ? 'Чтобы отправлять задания студентам ваших групп, введите код преподавателя. Код выдаёт автор приложения.'
            : 'Отправка ДЗ студентам сейчас недоступна: сервер не подключён.',
        action: serverOn
            ? FilledButton.icon(onPressed: () => showTeacherCodeDialog(context), icon: const Icon(Icons.vpn_key_rounded), label: const Text('Ввести код'))
            : null,
      );
    }

    final theme = Theme.of(context);
    final sent = ref.watch(teacherSentProvider);
    final teacherName = ref.watch(settingsProvider.select((s) => s.teacherName));
    final mismatch = teacherName != null && !sameTeacher(teacherName, session.teacher);

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showTeacherHomeworkSheet(context),
        icon: const Icon(Icons.send_rounded),
        label: const Text('Отправить ДЗ'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(teacherSentProvider);
          try {
            await ref.read(teacherSentProvider.future);
          } catch (_) {}
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.lg, Gap.lg, 104),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Gap.xs),
              child: Text('Домашка студентам', style: theme.textTheme.headlineMedium),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Gap.xs, Gap.xs, Gap.xs, Gap.md),
              child: Text('Подпись для студентов: ${session.teacher}', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ),
            if (mismatch)
              Container(
                margin: const EdgeInsets.only(bottom: Gap.md),
                padding: const EdgeInsets.all(Gap.md),
                decoration: BoxDecoration(color: theme.colorScheme.tertiaryContainer, borderRadius: BorderRadius.circular(Radii.md)),
                child: Text(
                  'Код выдан на «${session.teacher}», а вы выбрали в профиле «$teacherName». ДЗ будут подписаны именем из кода.',
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onTertiaryContainer),
                ),
              ),
            const Padding(padding: EdgeInsets.only(bottom: Gap.lg), child: _ComputerCard()),
            ...sent.when(
              loading: () => [const Padding(padding: EdgeInsets.all(Gap.xxl), child: Center(child: CircularProgressIndicator()))],
              error: (e, _) => [_SentError(error: e)],
              data: (items) => items.isEmpty
                  ? [
                      SizedBox(
                        height: (MediaQuery.sizeOf(context).height - 360).clamp(260.0, 640.0),
                        child: const EmptyState(
                          illustration: IllustrationKind.noHomework,
                          title: 'Вы пока ничего не отправляли',
                          subtitle: 'Нажмите «Отправить ДЗ»: выберите предмет и группы, и студенты увидят задание у себя во вкладке «Преподаватели».',
                        ),
                      ),
                    ]
                  : [
                      for (final (i, b) in items.indexed)
                        Reveal(key: ValueKey('sent-${b.id}'), index: i, child: _SentTile(batch: b)),
                    ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Вход для отправки ДЗ с компьютера в аудитории: открывает экран с QR и кодом.
class _ComputerCard extends StatelessWidget {
  const _ComputerCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      button: true,
      label: 'Отправить ДЗ с компьютера. Файлы с аудиторного компьютера: вход по QR-коду или коду',
      excludeSemantics: true,
      child: Material(
        color: scheme.primaryContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const WebLoginScreen())),
          child: Padding(
            padding: const EdgeInsets.all(Gap.lg),
            child: Row(children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(Radii.md)),
                child: Icon(Icons.computer_rounded, color: scheme.onPrimary),
              ),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Отправить ДЗ с компьютера', style: theme.textTheme.titleMedium?.copyWith(color: scheme.onPrimaryContainer)),
                  const SizedBox(height: 2),
                  Text(
                    'Файлы на аудиторном компьютере? Войдите там по QR или коду',
                    style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onPrimaryContainer.withValues(alpha: 0.85)),
                  ),
                ]),
              ),
              const SizedBox(width: Gap.xs),
              Icon(Icons.chevron_right_rounded, color: scheme.onPrimaryContainer),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Ошибка загрузки списка отправленного: нет связи, доступ отозван или сбой сервера.
class _SentError extends ConsumerWidget {
  const _SentError({required this.error});
  final Object error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final revoked = error is SharedApiException && (error as SharedApiException).code == 'bad_token';
    final message = error is SharedApiException ? (error as SharedApiException).message : 'Не удалось загрузить список: $error';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Gap.xl),
      child: Column(children: [
        Icon(revoked ? Icons.lock_outline_rounded : Icons.cloud_off_rounded, size: 40, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(height: Gap.md),
        Text(message, textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
        const SizedBox(height: Gap.lg),
        if (revoked)
          FilledButton(onPressed: () => ref.read(teacherSessionProvider.notifier).clear(), child: const Text('Ввести код заново'))
        else
          FilledButton(onPressed: () => ref.invalidate(teacherSentProvider), child: const Text('Повторить')),
      ]),
    );
  }
}

/// Одна отправка: предмет, текст, срок, группы и файлы; меню «Изменить / Удалить».
class _SentTile extends ConsumerWidget {
  const _SentTile({required this.batch});
  final TeacherHomeworkBatch batch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final styles = ref.watch(subjectStylesProvider);
    final tone = styles.tone(batch.subject, theme.brightness);
    final index = ref.watch(indexProvider).value;
    final titles = {for (final f in index?.forms ?? const []) for (final g in f.groups) g.id: g};
    String label(TeacherSentTarget t) {
      final g = titles[t.groupId];
      if (g == null) return t.groupId;
      if (t.subgroup == null) return g.title;
      return g.subgroups.where((s) => s.n == t.subgroup).map((s) => s.label).firstOrNull ?? '${g.title}, подгруппа ${t.subgroup}';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.sm),
      child: Material(
        color: tone.container,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg)),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.xs, Gap.md),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                WordFitText(styles.name(batch.subject), style: theme.textTheme.titleSmall?.copyWith(color: tone.onContainer)),
                const SizedBox(height: Gap.xs),
                Text(batch.text, style: theme.textTheme.bodyLarge?.copyWith(color: scheme.onSurface)),
                const SizedBox(height: Gap.sm),
                Row(children: [
                  Icon(Icons.event_rounded, size: 16, color: scheme.onSurfaceVariant),
                  const SizedBox(width: Gap.xs),
                  Flexible(
                    child: Text(
                      'к ${dateText(batch.dueDate)}${batch.kind == null ? '' : ' · ${batch.kind!.title.toLowerCase()}'}',
                      style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                ]),
                const SizedBox(height: Gap.sm),
                Wrap(spacing: Gap.xs, runSpacing: Gap.xs, children: [
                  for (final t in batch.targets)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: 2),
                      decoration: BoxDecoration(color: scheme.surface.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(8)),
                      child: Text(label(t), style: theme.textTheme.labelSmall?.copyWith(color: tone.onContainer)),
                    ),
                ]),
                GroupAttachmentStrip(files: batch.files, color: tone.accent, groupId: batch.targets.firstOrNull?.groupId),
              ]),
            ),
            PopupMenuButton<String>(
              tooltip: 'Действия с заданием',
              icon: Icon(Icons.more_vert_rounded, color: scheme.onSurfaceVariant),
              onSelected: (v) async {
                if (v == 'edit') {
                  await showTeacherHomeworkSheet(context, editing: batch);
                } else {
                  await _confirmDelete(context, ref);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Изменить')),
                PopupMenuItem(value: 'delete', child: Text('Удалить у студентов')),
              ],
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final actions = TeacherActions.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить ДЗ?'),
        content: const Text('Задание пропадёт у студентов всех групп, куда оно было отправлено.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Удалить')),
        ],
      ),
    );
    if (ok != true || batch.id == null) return;
    try {
      await actions.delete(batch.id!);
      messenger.showSnackBar(const SnackBar(content: Text('Удалено у студентов')));
    } on SharedApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}
