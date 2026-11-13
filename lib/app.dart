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
import 'ui/tokens.dart';

ThemeData buildTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final scheme = dark
      ? const ColorScheme(
          brightness: Brightness.dark,
          primary: Tw.indigo500,
          onPrimary: Colors.white,
          primaryContainer: Color(0xFF2E2A6B),
          onPrimaryContainer: Tw.indigo100,
          secondary: Tw.emerald400,
          onSecondary: Tw.slate950,
          secondaryContainer: Color(0xFF0F3B33),
          onSecondaryContainer: Color(0xFFA7F3D0),
          tertiary: Tw.violet500,
          onTertiary: Colors.white,
          tertiaryContainer: Color(0xFF3B2470),
          onTertiaryContainer: Color(0xFFEDE9FE),
          error: Tw.rose400,
          onError: Tw.slate950,
          errorContainer: Color(0xFF4C1424),
          onErrorContainer: Color(0xFFFFE4E6),
          surface: Tw.slate950,
          onSurface: Tw.slate100,
          onSurfaceVariant: Tw.slate400,
          surfaceContainerLowest: Color(0xFF01040F),
          surfaceContainerLow: Color(0xFF0A1122),
          surfaceContainer: Tw.slate900,
          surfaceContainerHigh: Tw.slate850,
          surfaceContainerHighest: Tw.slate800,
          outline: Tw.slate600,
          outlineVariant: Tw.slate800,
          inverseSurface: Tw.slate100,
          onInverseSurface: Tw.slate900,
          inversePrimary: Tw.indigo600,
          shadow: Colors.black,
          scrim: Colors.black,
        )
      : const ColorScheme(
          brightness: Brightness.light,
          primary: Tw.indigo600,
          onPrimary: Colors.white,
          primaryContainer: Tw.indigo100,
          onPrimaryContainer: Tw.indigo900,
          secondary: Tw.emerald600,
          onSecondary: Colors.white,
          secondaryContainer: Color(0xFFD1FAE5),
          onSecondaryContainer: Color(0xFF064E3B),
          tertiary: Tw.violet600,
          onTertiary: Colors.white,
          tertiaryContainer: Color(0xFFEDE9FE),
          onTertiaryContainer: Color(0xFF4C1D95),
          error: Tw.rose600,
          onError: Colors.white,
          errorContainer: Color(0xFFFFE4E6),
          onErrorContainer: Color(0xFF881337),
          surface: Tw.slate50,
          onSurface: Tw.slate900,
          onSurfaceVariant: Tw.slate500,
          surfaceContainerLowest: Colors.white,
          surfaceContainerLow: Colors.white,
          surfaceContainer: Tw.slate100,
          surfaceContainerHigh: Tw.slate100,
          surfaceContainerHighest: Tw.slate200,
          outline: Tw.slate400,
          outlineVariant: Tw.slate200,
          inverseSurface: Tw.slate900,
          onInverseSurface: Tw.slate100,
          inversePrimary: Tw.indigo300,
          shadow: Colors.black,
          scrim: Colors.black,
        );
  const radius = BorderRadius.all(Radius.circular(Tw.rXl));
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, fontFamily: Tw.font);
  final text = base.textTheme.copyWith(
    displaySmall: base.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1),
    headlineMedium: base.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.6),
    headlineSmall: base.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.4),
    titleLarge: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.2),
    titleMedium: base.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    labelLarge: base.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
  );
  OutlineInputBorder border(Color c, [double w = 1]) =>
      OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: c, width: w));
  return base.copyWith(
    visualDensity: VisualDensity.standard,
    textTheme: text,
    scaffoldBackgroundColor: scheme.surface,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? Tw.slate900 : Colors.white,
      border: border(dark ? Tw.slate700 : Tw.slate300),
      enabledBorder: border(dark ? Tw.slate700 : Tw.slate300),
      focusedBorder: border(scheme.primary, 2),
      errorBorder: border(scheme.error),
      focusedErrorBorder: border(scheme.error, 2),
      labelStyle: TextStyle(color: dark ? Tw.slate400 : Tw.slate500),
      hintStyle: TextStyle(color: dark ? Tw.slate500 : Tw.slate400),
      prefixIconColor: dark ? Tw.slate400 : Tw.slate500,
      suffixIconColor: dark ? Tw.slate400 : Tw.slate500,
      contentPadding: const EdgeInsets.symmetric(horizontal: Tw.s4, vertical: 15),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 52),
        shape: const RoundedRectangleBorder(borderRadius: radius),
        textStyle: const TextStyle(fontFamily: Tw.font, fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 52),
        shape: const RoundedRectangleBorder(borderRadius: radius),
        side: BorderSide(color: dark ? Tw.slate700 : Tw.slate300),
        foregroundColor: scheme.onSurface,
        textStyle: const TextStyle(fontFamily: Tw.font, fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(textStyle: const TextStyle(fontFamily: Tw.font, fontWeight: FontWeight.w600)),
    ),
    cardTheme: CardTheme(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: dark ? Tw.slate900 : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(Radius.circular(Tw.r2xl)),
        side: BorderSide(color: dark ? Tw.slate800 : Tw.slate200),
      ),
    ),
    dividerTheme: DividerThemeData(color: dark ? Tw.slate800 : Tw.slate200, space: 1),
    chipTheme: base.chipTheme.copyWith(shape: const StadiumBorder(), side: BorderSide(color: dark ? Tw.slate700 : Tw.slate300)),
    listTileTheme: const ListTileThemeData(minVerticalPadding: 10),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: const RoundedRectangleBorder(borderRadius: radius),
      backgroundColor: dark ? Tw.slate800 : Tw.slate900,
      contentTextStyle: const TextStyle(fontFamily: Tw.font, color: Colors.white),
    ),
    dialogTheme: DialogTheme(
      backgroundColor: dark ? Tw.slate900 : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(Tw.r3xl))),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: dark ? Tw.slate900 : Colors.white,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Tw.r3xl))),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: text.titleLarge?.copyWith(color: scheme.onSurface),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: dark ? Tw.slate900 : Colors.white,
      indicatorColor: scheme.primary.withOpacity(dark ? 0.22 : 0.12),
      surfaceTintColor: Colors.transparent,
      labelTextStyle: WidgetStateProperty.all(const TextStyle(fontFamily: Tw.font, fontSize: 12, fontWeight: FontWeight.w600)),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: dark ? Tw.slate900 : Colors.white,
      indicatorColor: scheme.primary.withOpacity(dark ? 0.22 : 0.12),
    ),
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

  /// Android back button / back swipe. The lock screen has its own navigator
  /// (it sits above every route), so its screens are popped here; otherwise
  /// the normal navigator handles it.
  @override
  Future<bool> didPopRoute() async {
    final lockNav = _lockNavKey.currentState;
    if (lockNav != null && lockNav.mounted && lockNav.canPop()) {
      lockNav.pop();
      return true;
    }
    return false;
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
