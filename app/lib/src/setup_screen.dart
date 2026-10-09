import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'chrome.dart';
import 'session.dart';
import 'setup_permissions.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  String _digits = '';
  var _accepted = false;
  var _busy = false;
  var _askedPermissions = false;

  @override
  void initState() {
    super.initState();
    FirebaseAnalytics.instance.logScreenView(screenName: 'setup');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final session = SessionHost.of(context);
      final l10n = AppLocalizations.of(context);
      Speaker.say(session.lang, l10n.continueAction);
    });
  }

  Future<void> _askPermissions({String? speak}) async {
    final session = SessionHost.of(context);
    if (speak != null) await Speaker.say(session.lang, speak);
    await requestSetupPermissions();
    _askedPermissions = true;
  }

  Future<void> _go() async {
    if (_digits.length != 10 || !_accepted || _busy) return;
    final session = SessionHost.of(context);
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    if (!_askedPermissions) await requestSetupPermissions();
    final located = await session.locate();
    if (!located) {
      if (mounted) {
        setState(() => _busy = false);
        await Speaker.say(session.lang, l10n.tryAgain);
      }
      return;
    }
    try {
      await session.setWhatsapp('+91$_digits');
    } catch (_) {
      if (mounted) await Speaker.say(session.lang, l10n.tryAgain);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final session = SessionHost.of(context);
    return Paged(
      page: 3,
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.only(left: 16, top: 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'WhatsApp',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              Row(
                children: [
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      '+91 $_digits',
                      style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w700),
                    ),
                  ),
                  BigIcon(
                    icon: Icons.check,
                    filled: _digits.length == 10 && _accepted,
                    label: l10n.continueAction,
                    onTap: _go,
                  ),
                  const SizedBox(width: 8),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: GridView.count(
                  crossAxisCount: 3,
                  childAspectRatio: 1.8,
                  padding: const EdgeInsets.all(24),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  children: [
                    for (final key in [
                      '1',
                      '2',
                      '3',
                      '4',
                      '5',
                      '6',
                      '7',
                      '8',
                      '9',
                      'del',
                      '0',
                    ])
                      if (key == 'del')
                        BigIcon(
                          icon: Icons.backspace,
                          onTap: () {
                            if (_digits.isEmpty) return;
                            setState(
                              () => _digits = _digits.substring(0, _digits.length - 1),
                            );
                          },
                        )
                      else
                        _Digit(
                          key: ValueKey(key),
                          digit: key,
                          onTap: () {
                            if (_digits.length >= 10) return;
                            setState(() => _digits += key);
                          },
                        ),
                  ],
                ),
              ),
              Wrap(
                alignment: WrapAlignment.spaceEvenly,
                spacing: 8,
                runSpacing: 8,
                children: [
                  BigIcon(
                    icon: _accepted ? Icons.check_circle : Icons.circle_outlined,
                    label: l10n.accept,
                    color: _accepted ? const Color(0xFF0F6E56) : null,
                    onTap: () async {
                      final next = !_accepted;
                      setState(() => _accepted = next);
                      if (next) await _askPermissions();
                    },
                  ),
                  BigIcon(
                    icon: Icons.description,
                    label: l10n.terms,
                    onTap: () {
                      unawaited(Speaker.say(session.lang, l10n.termsBody));
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (context) => Paged(
                            page: 3,
                            child: Scaffold(
                              body: SafeArea(
                                child: Column(
                                  children: [
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: BigIcon(
                                        icon: Icons.arrow_back,
                                        label: l10n.back,
                                        onTap: () => Navigator.pop(context),
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.all(24),
                                      child: Text(
                                        l10n.termsBody,
                                        style: const TextStyle(fontSize: 22),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Wrap(
                  alignment: WrapAlignment.spaceEvenly,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    BigIcon(
                      icon: Icons.place,
                      label: l10n.location,
                      onTap: () => _askPermissions(speak: l10n.location),
                    ),
                    BigIcon(
                      icon: Icons.photo_camera,
                      label: l10n.camera,
                      onTap: () => _askPermissions(speak: l10n.camera),
                    ),
                    BigIcon(
                      icon: Icons.mic,
                      label: l10n.mic,
                      onTap: () => _askPermissions(speak: l10n.mic),
                    ),
                    BigIcon(
                      icon: Icons.photo,
                      label: l10n.photos,
                      onTap: () => _askPermissions(speak: l10n.photos),
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

class _Digit extends StatelessWidget {
  const _Digit({required this.digit, required this.onTap, super.key});

  final String digit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: digit,
      child: Material(
        color: const Color(0xFFE7F2EE),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Center(
            child: Text(digit, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700)),
          ),
        ),
      ),
    );
  }
}
