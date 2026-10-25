// Русские названия дней и месяцев, склонения — без лишних библиотек.

const weekdayNames = ['', 'понедельник', 'вторник', 'среда', 'четверг', 'пятница', 'суббота', 'воскресенье'];
const weekdayTitles = ['', 'Понедельник', 'Вторник', 'Среда', 'Четверг', 'Пятница', 'Суббота', 'Воскресенье'];
const weekdayShort = ['', 'Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
const _monthsGenitive = [
  '', 'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
  'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
];

/// «четверг, 8 октября»
String dayTitle(DateTime day) => '${weekdayNames[day.weekday]}, ${day.day} ${_monthsGenitive[day.month]}';

/// «8 октября»
String dateText(DateTime day) => '${day.day} ${_monthsGenitive[day.month]}';

/// Склонение: plural(5, 'минута', 'минуты', 'минут') → «минут».
String plural(int n, String one, String few, String many) {
  final mod10 = n % 10, mod100 = n % 100;
  if (mod10 == 1 && mod100 != 11) return one;
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) return few;
  return many;
}

/// «1 ч 30 мин», «45 мин»
String durationText(Duration d) {
  final hours = d.inHours, minutes = d.inMinutes % 60;
  if (hours == 0) return '$minutes мин';
  if (minutes == 0) return '$hours ч';
  return '$hours ч $minutes мин';
}

/// «обновлено 2 дня назад»
String agoText(DateTime moment, DateTime now) {
  final d = now.difference(moment);
  if (d.inMinutes < 1) return 'только что';
  if (d.inMinutes < 60) return '${d.inMinutes} ${plural(d.inMinutes, 'минуту', 'минуты', 'минут')} назад';
  if (d.inHours < 24) return '${d.inHours} ${plural(d.inHours, 'час', 'часа', 'часов')} назад';
  return '${d.inDays} ${plural(d.inDays, 'день', 'дня', 'дней')} назад';
}

/// Короткое название предмета для виджета: «Технологическое предпринимательство» → «Технол. предпр.».
/// Сначала выкидываем предлоги, потом по одному сокращаем самые длинные слова — пока название не влезет.
/// Слова с латиницей и дефисом не трогаем (Python, ViPNet, Бизнес-планирование).
String shortSubject(String subject, {int maxLength = 18}) {
  if (subject.length <= maxLength) return subject;

  const fillers = {'и', 'в', 'на', 'для', 'по', 'о', 'об', 'с', 'к'};
  final words = [
    for (final w in subject.split(' '))
      if (!fillers.contains(w.toLowerCase())) w,
  ];

  bool canShorten(String w) =>
      w.length > 5 && !w.endsWith('.') && !w.contains('-') && !RegExp(r'[A-Za-z]').hasMatch(w) && w != w.toUpperCase();

  String abbreviate(String w) {
    // обрезаем так, чтобы не оставить гласную на конце («Технол.», а не «Техно.»)
    var cut = 5;
    while (cut > 3 && 'аеёиоуыэюяй'.contains(w[cut - 1].toLowerCase())) {
      cut--;
    }
    return '${w.substring(0, cut)}.';
  }

  String joined() => words.join(' ');
  while (joined().length > maxLength) {
    // самое длинное слово из тех, что ещё можно сократить
    var longest = -1;
    for (var i = 0; i < words.length; i++) {
      if (canShorten(words[i]) && (longest == -1 || words[i].length > words[longest].length)) longest = i;
    }
    if (longest == -1) break;
    words[longest] = abbreviate(words[longest]);
  }

  final result = joined();
  return result.length <= maxLength + 6 ? result : '${result.substring(0, maxLength + 5)}…';
}

/// Дата расписания из его версии («2026-10-09T22:47:56Z-9cffa803» → 9 октября). Пусто, если версию не разобрать.
DateTime? scheduleDate(String? version) {
  if (version == null || version.length < 10) return null;
  final d = DateTime.tryParse(version.substring(0, 10));
  return d == null ? null : DateTime.utc(d.year, d.month, d.day);
}

/// Склеивает подпись для экранной читалки: «Кутаев А.Х.» и «Вместе с группами» → «Кутаев А.Х. Вместе с группами» (без двойной точки).
String joinSentences(String first, Iterable<String> rest) {
  var out = first;
  for (final r in rest) {
    out += '${out.endsWith('.') ? ' ' : '. '}$r';
  }
  return out;
}
