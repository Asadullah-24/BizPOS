import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'core/app_state.dart';
import 'core/i18n.dart';
import 'core/db.dart';
import 'core/license.dart';
import 'services/alert_service.dart';
import 'services/cloud_service.dart';
import 'ui/screens/auth/welcome_screen.dart';
import 'services/drive_service.dart';
import 'ui/screens/lock_screen.dart';
import 'ui/screens/onboarding_screen.dart';
import 'ui/screens/shell.dart';

ThemeData buildTheme(Brightness b) {
  final dark = b == Brightness.dark;
  var scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF14B8A6), brightness: b);
  if (dark) {
    scheme = scheme.copyWith(
      surface: const Color(0xFF0B1220),
      surfaceContainerLowest: const Color(0xFF070B14),
      surfaceContainerLow: const Color(0xFF0F172A),
      surfaceContainer: const Color(0xFF111A2E),
      surfaceContainerHigh: const Color(0xFF16213A),
      surfaceContainerHighest: const Color(0xFF1C2944),
    );
  }
  const radius = BorderRadius.all(Radius.circular(12));
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    visualDensity: VisualDensity.standard,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest.withOpacity(0.5),
      border: const OutlineInputBorder(borderRadius: radius, borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 52),
        shape: const RoundedRectangleBorder(borderRadius: radius),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 52),
        shape: const RoundedRectangleBorder(borderRadius: radius),
      ),
    ),
    cardTheme: const CardTheme(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: radius),
    ),
    listTileTheme: const ListTileThemeData(minVerticalPadding: 10),
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(backgroundColor: scheme.surface, surfaceTintColor: Colors.transparent, centerTitle: false),
    navigationBarTheme: NavigationBarThemeData(backgroundColor: scheme.surfaceContainerLow, indicatorColor: scheme.primaryContainer),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: ZoomPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    }),
  );
}

class BizPosApp extends StatefulWidget {
  const BizPosApp({super.key});

  @override
  State<BizPosApp> createState() => _BizPosAppState();
}

class _BizPosAppState extends State<BizPosApp> with WidgetsBindingObserver {
  DateTime? _pausedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final app = AppState.instance;
    if (state == AppLifecycleState.paused) {
      _pausedAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final mins = app.autoLockMinutes;
      if (_pausedAt != null && mins > 0 && DateTime.now().difference(_pausedAt!).inMinutes >= mins) {
        app.lock();
      }
      _pausedAt = null;
      DriveService.instance.autoBackup();
      LicenseService.instance.load();
      if (!app.locked) AlertService.runChecks();
    }
  }

  final _navKey = GlobalKey<NavigatorState>();
  final _lockNavKey = GlobalKey<NavigatorState>();
  bool _wasLocked = true;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    context.watch<LicenseService>();
    final cloud = context.watch<CloudService>();
    final locked = app.onboarded && app.locked;
    final needsAccount = cloud.configured && cloud.ready && !cloud.signedIn && Local.prefs.getBool('offline_mode') != true;
    final themeKey = app.settings['theme'] ?? 'dark';
    final mode = switch (themeKey) { 'light' => ThemeMode.light, 'system' => ThemeMode.system, _ => ThemeMode.dark };
    if (locked && !_wasLocked) {
      // Close open screens so the next person starts from the dashboard.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _navKey.currentState?.popUntil((r) => r.isFirst);
      });
    }
    _wasLocked = locked;
    return MaterialApp(
      title: 'BizPOS',
      navigatorKey: _navKey,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: mode,
      locale: Locale(app.language),
      supportedLocales: [for (final l in I18n.languages.keys) Locale(l)],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // Free to start: create an account (or go offline), set up the shop, sell.
      home: app.onboarded ? const Shell() : (needsAccount ? const WelcomeScreen() : const OnboardingScreen()),
      // The lock screen sits above every route, so locking never loses the
      // screen underneath and nothing behind it can be reached. It has its own
      // navigator so the super admin screens can open from it.
      builder: (context, child) => Stack(fit: StackFit.expand, children: [
        if (child != null) child,
        if (locked)
          Positioned.fill(
            child: HeroControllerScope.none(
              child: Navigator(
                key: _lockNavKey,
                onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => const LockScreen()),
              ),
            ),
          ),
      ]),
    );
  }
}
