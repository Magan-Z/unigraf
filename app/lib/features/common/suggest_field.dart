// Поле ввода с подсказками: пока оно в фокусе, под ним появляются подходящие варианты (предмет, аудитория, преподаватель).
// Нажатие на вариант подставляет его в поле. Свой вариант вписать по-прежнему можно.

import 'package:flutter/material.dart';

import '../../domain/pair_suggestions.dart';
import '../../theme/tokens.dart';

class SuggestField extends StatefulWidget {
  const SuggestField({super.key, required this.controller, required this.label, required this.options, this.onChanged});

  final TextEditingController controller;
  final String label;
  final List<String> options;
  final VoidCallback? onChanged;

  @override
  State<SuggestField> createState() => _SuggestFieldState();
}

class _SuggestFieldState extends State<SuggestField> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_refresh);
    widget.controller.addListener(_refresh);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refresh);
    _focus.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _pick(String value) {
    widget.controller.value = TextEditingValue(text: value, selection: TextSelection.collapsed(offset: value.length));
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final matches = _focus.hasFocus ? PairSuggestions.matching(widget.options, widget.controller.text) : const <String>[];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TextField(
        controller: widget.controller,
        focusNode: _focus,
        onChanged: (_) => widget.onChanged?.call(),
        decoration: InputDecoration(labelText: widget.label),
      ),
      if (matches.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: Gap.sm),
          child: Wrap(spacing: Gap.sm, runSpacing: 0, children: [
            for (final m in matches)
              ActionChip(
                label: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 220), child: Text(m, overflow: TextOverflow.ellipsis)),
                visualDensity: VisualDensity.compact,
                onPressed: () => _pick(m),
              ),
          ]),
        ),
    ]);
  }
}
