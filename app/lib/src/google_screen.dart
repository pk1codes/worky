import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

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
  String? _error;

  @override
  void initState() {
    super.initState();
    FirebaseAnalytics.instance.logScreenView(screenName: 'google');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final session = SessionHost.of(context);
      unawaited(
        Speaker.say(session.lang, AppLocalizations.of(context).signInGoogle),
      );
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Worky',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 32,
                  color: Color(0xFF14281D),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(24, 8, 24, 16),
                child: Text(
                  'Find nearby work. Message or call. The exact place stays hidden.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: Color(0xFF14281D)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                child: Text(
                  l10n.signInGoogle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 20,
                    color: Color(0xFF14281D),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _busy
                  ? const SizedBox(
                      width: 72,
                      height: 64,
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : BigIcon(
                      icon: Icons.account_circle,
                      filled: true,
                      label: l10n.google,
                      onTap: () async {
                        setState(() {
                          _busy = true;
                          _error = null;
                        });
                        try {
                          await session.signIn();
                        } catch (error) {
                          if (!mounted) return;
                          setState(() => _error = _signInError(error));
                          await Speaker.say(session.lang, l10n.tryAgain);
                        } finally {
                          if (mounted) setState(() => _busy = false);
                        }
                      },
                    ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      color: Color(0xFF14281D),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

String _signInError(Object error) {
  if (error is GoogleSignInException) {
    final detail = error.description;
    final code = error.code.name;
    if (detail == null || detail.isEmpty) return code;
    return '$code: $detail';
  }
  return error.toString();
}
