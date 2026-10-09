import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'chrome.dart';
import 'langs.dart';
import 'session.dart';

class LanguageScreen extends StatefulWidget {
  const LanguageScreen({super.key});

  @override
  State<LanguageScreen> createState() => _LanguageScreenState();
}

class _LanguageScreenState extends State<LanguageScreen> {
  String? _armed;

  @override
  Widget build(BuildContext context) {
    final session = SessionHost.of(context);
    return Paged(
      page: 1,
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
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
                        selected: _armed == code,
                        onTap: () async {
                          if (_armed != code) {
                            setState(() => _armed = code);
                            await Speaker.clip(code);
                            return;
                          }
                          await session.setLang(code);
                        },
                      ),
                  ],
                ),
              ),
              if (_armed != null)
                BigIcon(
                  icon: Icons.check,
                  filled: true,
                  label: lookupAppLocalizations(
                    Locale(_armed!),
                  ).continueAction,
                  onTap: () => session.setLang(_armed!),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
