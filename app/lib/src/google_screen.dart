import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'chrome.dart';
import 'session.dart';

class GoogleScreen extends StatefulWidget {
  const GoogleScreen({super.key});

  @override
  State<GoogleScreen> createState() => _GoogleScreenState();
}

class _GoogleScreenState extends State<GoogleScreen> {
  var _busy = false;

  @override
  void initState() {
    super.initState();
    FirebaseAnalytics.instance.logScreenView(screenName: 'google');
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final session = SessionHost.of(context);
      unawaited(Speaker.say(session.lang, 'Google'));
      await session.trySilent();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final session = SessionHost.of(context);
    return Paged(
      page: 2,
      child: Scaffold(
        body: Center(
          child: BigIcon(
            icon: Icons.account_circle,
            filled: true,
            label: l10n.google,
            onTap: _busy
                ? null
                : () async {
                    setState(() => _busy = true);
                    try {
                      await session.signIn();
                    } catch (_) {
                      if (mounted)
                        await Speaker.say(session.lang, l10n.tryAgain);
                    } finally {
                      if (mounted) setState(() => _busy = false);
                    }
                  },
          ),
        ),
      ),
    );
  }
}
