import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsBinding;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_state.dart';
import 'config.dart';
import 'data/remote/shared_api.dart';
import 'domain/teacher.dart';
import 'background/background_sync.dart';
import 'features/home_shell.dart';
import 'features/update_banner.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'theme/app_theme.dart';
import 'update_check.dart';
import 'usage_ping.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // В браузере доступность Flutter по умолчанию выключена, пока человек не нажмёт скрытую кнопку «Enable accessibility»;
  // VoiceOver на iPhone её не находит. Включаем сразу, чтобы экранные читалки видели подписи элементов.
  if (kIsWeb) SemanticsBinding.instance.ensureSemantics();
  final prefs = await SharedPreferences.getInstance();
  // Раз в ~6 часов проверяет обновления, даже когда приложение закрыто (только Android; в браузере такого нет)
  if (!kIsWeb) registerBackgroundSync();
  runApp(ProviderScope(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    child: const UniGrafApp(),
  ));
  // Анонимный счётчик пользователей: в фоне, через несколько секунд, чтобы не отнимать время у запуска
  if (sharedApiUrl.isNotEmpty) {
    Future<void>.delayed(
      const Duration(seconds: 4),
      () => sendUsagePing(prefs: prefs, api: SharedApi(sharedApiUrl, sharedApiKey), now: DateTime.now()),
    );
  }
}

/// Проверочный режим веб-версии: адрес …/app/?scroll=ios включает «айфоновскую» прокрутку (длинный плавный разгон
/// и отскок на краях) вместо «андроидовской». В браузере Flutter сам считает разгон списка, поэтому ощущение
/// от прокрутки отличается от системного; это позволяет сравнить два варианта на телефоне.
final bool _iosScroll = kIsWeb && Uri.base.queryParameters['scroll'] == 'ios';

class _IosScrollBehavior extends MaterialScrollBehavior {
  const _IosScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) => const BouncingScrollPhysics();
}

class UniGrafApp extends ConsumerWidget {
  const UniGrafApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    // Версия приложения устарела настолько, что пользоваться ею нельзя — только экран «Нужно обновить»
    final updateRequired = ref.watch(updateStatusProvider) == UpdateStatus.required;
    // Если выбранной группы больше нет в расписании (например, новый семестр) — снова предлагаем выбрать группу
    final index = ref.watch(indexProvider).value;
    final profile = settings.profile;
    final needsOnboarding = settings.role == UserRole.teacher
        ? settings.teacherName == null
        : profile == null || (index != null && index.findGroup(profile.groupId) == null);

    // По умолчанию — фирменные цвета; в настройках можно включить цвета из обоев (Material You, Android 12+)
    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        ThemeData theme(Brightness b, ColorScheme? dynamic) => buildTheme(
              resolveScheme(
                brightness: b,
                dynamicScheme: settings.useDynamicColor ? dynamic : null,
                palette: settings.palette,
                amoled: settings.amoled,
              ),
            );
        return MaterialApp(
          title: 'UniGraf',
          debugShowCheckedModeBanner: false,
          scrollBehavior: _iosScroll ? const _IosScrollBehavior() : null,
          themeMode: settings.themeMode,
          theme: theme(Brightness.light, lightDynamic),
          darkTheme: theme(Brightness.dark, darkDynamic),
          builder: (context, child) => UpdateWatcher(child: child ?? const SizedBox.shrink()),
          home: updateRequired ? const UpdateRequiredScreen() : (needsOnboarding ? const OnboardingScreen() : const HomeShell()),
        );
      },
    );
  }
}
