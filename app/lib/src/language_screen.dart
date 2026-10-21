import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'chrome.dart';
import 'langs.dart';
import 'session.dart';

Set<String> toggleSpoken(Set<String> spoken, String code) {
  final next = {...spoken};
  if (!next.add(code)) next.remove(code);
  return next;
}

class LanguageScreen extends StatefulWidget {
  const LanguageScreen({this.popOnPick = false, super.key});

  final bool popOnPick;

  @override
  State<LanguageScreen> createState() => _LanguageScreenState();
}

class _LanguageScreenState extends State<LanguageScreen> {
  var _busy = false;
  Set<String>? _spoken;

  Set<String> _current(Session session) => _spoken ??= {...session.spoken};

  Future<void> _pick(Session session, String code) async {
    if (widget.popOnPick) {
      if (_busy) return;
      _busy = true;
      unawaited(Speaker.clip(code));
      await session.setSpoken({code});
      await session.setLang(code);
      if (mounted) Navigator.pop(context);
      return;
    }
    final next = toggleSpoken(_current(session), code);
    _spoken = next;
    if (next.contains(code)) unawaited(Speaker.clip(code));
    setState(() {});
    await session.setSpoken(next);
  }

  Future<void> _continue(Session session) async {
    final spoken = _current(session);
    if (_busy || spoken.isEmpty) return;
    _busy = true;
    final lang = spoken.first;
    await session.setSpoken(spoken);
    await session.setLang(lang);
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
                        selected: widget.popOnPick
                            ? session.lang == code
                            : _current(session).contains(code),
                        onTap: () => _pick(session, code),
                      ),
                  ],
                ),
              ),
              if (!widget.popOnPick)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: FilledButton(
                      onPressed: _current(session).isEmpty
                          ? null
                          : () => _continue(session),
                      child: Text(l10n.continueAction),
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
