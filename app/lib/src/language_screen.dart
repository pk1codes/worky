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
  final _picked = <String>[];

  String? get _first => _picked.isEmpty ? null : _picked.first;

  Future<void> _save(Session session) async {
    final first = _first;
    if (first == null) return;
    await session.setSpoken(_picked.toSet());
    await session.setLang(first);
  }

  @override
  Widget build(BuildContext context) {
    final session = SessionHost.of(context);
    final l10n = AppLocalizations.of(context);
    final first = _first;
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
                        color: Color(0xFF16332C),
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
                        selected: _picked.contains(code),
                        onTap: () async {
                          if (widget.popOnPick) {
                            await session.setLang(code);
                            if (context.mounted) Navigator.pop(context);
                            return;
                          }
                          final added = !_picked.contains(code);
                          setState(() {
                            if (added) {
                              _picked.add(code);
                            } else if (_picked.length > 1) {
                              _picked.remove(code);
                            }
                          });
                          if (_picked.contains(code)) await Speaker.clip(code);
                        },
                      ),
                  ],
                ),
              ),
              if (first != null)
                BigIcon(
                  icon: Icons.check,
                  filled: true,
                  label: lookupAppLocalizations(Locale(first)).continueAction,
                  onTap: () => _save(session),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
