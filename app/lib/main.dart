import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'firebase_options.dart';
import 'l10n/app_localizations.dart';
import 'src/browse_screen.dart';
import 'src/config.dart';
import 'src/google_screen.dart';
import 'src/language_screen.dart';
import 'src/session.dart';
import 'src/setup_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  if (kUseEmulator) {
    await FirebaseAuth.instance.useAuthEmulator(kHost, 9099);
  } else if (kIsWeb) {
    if (kAppCheckSiteKey.isNotEmpty) {
      await FirebaseAppCheck.instance.activate(
        webProvider: ReCaptchaEnterpriseProvider(kAppCheckSiteKey),
      );
    }
  } else {
    await FirebaseAppCheck.instance.activate(
      providerAndroid: kDebugMode
          ? const AndroidDebugProvider()
          : const AndroidPlayIntegrityProvider(),
    );
    await GoogleSignIn.instance.initialize();
  }
  try {
    await FirebaseAnalytics.instance.logAppOpen();
  } catch (_) {}
  final session = Session(FirebaseAuth.instance);
  await session.boot();
  runApp(WorkyApp(session: session));
}

class WorkyApp extends StatelessWidget {
  const WorkyApp({required this.session, super.key});

  final Session session;

  @override
  Widget build(BuildContext context) {
    return SessionHost(
      session: session,
      child: AnimatedBuilder(
        animation: session,
        builder: (context, _) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            locale: Locale(session.lang ?? 'en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: ThemeData(
              useMaterial3: true,
              colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0F6E56)),
              iconTheme: const IconThemeData(size: 32),
            ),
            home: Gate(
              key: ValueKey(
                '${session.ready}|${session.lang}|${session.user?.uid}|${session.whatsapp}',
              ),
            ),
          );
        },
      ),
    );
  }
}

class Gate extends StatelessWidget {
  const Gate({super.key});

  @override
  Widget build(BuildContext context) {
    final session = SessionHost.of(context);
    if (!session.ready) {
      return const Scaffold(body: Center(child: Icon(Icons.circle, size: 28)));
    }
    if (session.lang == null) return const LanguageScreen();
    if (session.user == null) return const GoogleScreen();
    if (session.whatsapp == null || session.whatsapp!.isEmpty) return const SetupScreen();
    return const BrowseScreen();
  }
}
