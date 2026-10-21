// Описание личных правок простыми словами — для списка «Мои правки на этот день».

import 'assessments.dart';
import 'models.dart';

String describeOverride(Override o) {
  final base = _describeBase(o);
  return o.repeatWeekly ? '$base · каждую неделю' : base;
}

String _describeBase(Override o) {
  final pair = '${o.pair} пара';
  switch (o.type) {
    case OverrideType.cancel:
      return o.matchSubject == null ? 'Отменена: $pair' : 'Отменена: $pair (${o.matchSubject})';
    case OverrideType.replace:
      final kind = o.kind;
      final note = kind == null ? o.note : visibleNote(kind, o.note);
      final changes = [
        if (o.subject != null) 'предмет: ${o.subject}',
        if (o.teacher != null) 'преподаватель: ${o.teacher}',
        if (o.room != null) 'аудитория: ${o.room}',
        if (note != null) 'заметка: $note',
      ];
      if (kind != null && kind.isAssessment) {
        final subject = o.matchSubject == null ? '' : ' (${o.matchSubject})';
        return '${kind.title}: $pair$subject${changes.isEmpty ? '' : ' — ${changes.join(', ')}'}';
      }
      return 'Изменена: $pair${changes.isEmpty ? '' : ' — ${changes.join(', ')}'}';
    case OverrideType.add:
      final parts = [o.subject ?? 'Занятие', if (o.room != null) o.room!, if (o.teacher != null) o.teacher!];
      final title = o.kind != null && o.kind!.isAssessment ? o.kind!.title : 'Своя пара';
      return '$title: $pair — ${parts.join(', ')}';
  }
}

/// Пустая строка из поля ввода → null (то есть «не менять»).
String? blankToNull(String text) {
  final trimmed = text.trim();
  return trimmed.isEmpty ? null : trimmed;
}
