import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'chrome.dart';
import 'langs.dart';
import 'session.dart';

class LanguageScreen extends StatefulWidget {
  const LanguageScreen({this.popOnPick = false, super.key});

  final bool popOnPick;

  @override
  State<LanguageScreen> createState() => _LanguageScreenState();
}

class _LanguageScreenState extends State<LanguageScreen> {
  var _busy = false;

  Future<void> _pick(Session session, String code) async {
    if (_busy) return;
    _busy = true;
    unawaited(Speaker.clip(code));
    await session.setSpoken({code});
    await session.setLang(code);
    if (widget.popOnPick && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final session = SessionHost.of(context);
    final l10n = AppLocalizations.of(context);
    return Paged(
      page: 1,
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              if (!widget.popOnPick)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      l10n.speakThese,
                      style: const TextStyle(
                        fontSize: 16,
                        color: Color(0xFF14281D),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: GridView.count(
                  crossAxisCount: 2,
                  padding: const EdgeInsets.all(16),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 2.2,
                  children: [
                    for (final code in kLangs)
                      LangTile(
                        code: code,
                        uniform: true,
                        selected: session.lang == code,
                        onTap: () => _pick(session, code),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
