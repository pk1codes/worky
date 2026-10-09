import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import 'admin_screen.dart';
import 'api.dart';
import 'chrome.dart';
import 'langs.dart';
import 'language_screen.dart';
import 'post_screen.dart';
import 'session.dart';

class MineScreen extends StatefulWidget {
  const MineScreen({super.key});

  @override
  State<MineScreen> createState() => _MineScreenState();
}

class _MineScreenState extends State<MineScreen> {
  List<FeedPost> _posts = [];
  var _loading = true;
  String? _armedDelete;
  var _armedAccount = false;

  @override
  void initState() {
    super.initState();
    FirebaseAnalytics.instance.logScreenView(screenName: 'mine');
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Speaker.say(SessionHost.of(context).lang, AppLocalizations.of(context).mine);
      await _load();
    });
  }

  Future<void> _load() async {
    try {
      final posts = await SessionHost.of(context).api.mine();
      if (mounted) {
        setState(() {
          _posts = posts;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final session = SessionHost.of(context);
    return Paged(
      page: 6,
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Row(
                children: [
                  BigIcon(icon: Icons.arrow_back, label: l10n.back, onTap: () => Navigator.pop(context)),
                  const Spacer(),
                  BigIcon(
                    icon: Icons.volume_up,
                    label: l10n.mine,
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(builder: (_) => const LanguageScreen()),
                      );
                      if (mounted) setState(() {});
                    },
                  ),
                  if (session.admin)
                    BigIcon(
                      icon: Icons.category,
                      label: l10n.admin,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(builder: (_) => const AdminScreen()),
                      ),
                    ),
                ],
              ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView(
                        children: [
                          for (final post in _posts)
                            Column(
                              children: [
                                Image.network(
                                  post.posterUrl,
                                  height: 160,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => const SizedBox(height: 80),
                                ),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                  children: [
                                    BigIcon(
                                      icon: Icons.edit,
                                      label: l10n.edit,
                                      onTap: () async {
                                        await Navigator.of(context).push(
                                          MaterialPageRoute<void>(builder: (_) => PostScreen(edit: post)),
                                        );
                                        await _load();
                                      },
                                    ),
                                    BigIcon(
                                      icon: post.status == 'paused' ? Icons.play_arrow : Icons.pause,
                                      label: post.status == 'paused' ? l10n.resume : l10n.pause,
                                      onTap: () async {
                                        await session.api.pause(post.id, post.status != 'paused');
                                        await _load();
                                      },
                                    ),
                                    BigIcon(
                                      icon: Icons.delete,
                                      label: l10n.delete,
                                      color: _armedDelete == post.id ? Colors.red : null,
                                      onTap: () async {
                                        if (_armedDelete != post.id) {
                                          setState(() => _armedDelete = post.id);
                                          await Speaker.say(session.lang, l10n.delete);
                                          return;
                                        }
                                        await session.api.deletePost(post.id);
                                        await _load();
                                      },
                                    ),
                                    BigIcon(
                                      icon: Icons.share,
                                      label: l10n.share,
                                      onTap: () => SharePlus.instance.share(ShareParams(text: post.categoryId)),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                        ],
                      ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  BigIcon(
                    icon: Icons.description,
                    label: l10n.terms,
                    onTap: () => Speaker.say(session.lang, l10n.termsBody),
                  ),
                  BigIcon(
                    icon: Icons.mail_outline,
                    label: l10n.contact,
                    onTap: () => launchUrl(Uri.parse('mailto:$kSupportEmail')),
                  ),
                  BigIcon(
                    icon: Icons.no_accounts,
                    label: l10n.deleteAccount,
                    color: _armedAccount ? Colors.red : null,
                    onTap: () async {
                      if (!_armedAccount) {
                        setState(() => _armedAccount = true);
                        await Speaker.say(session.lang, l10n.deleteAccount);
                        return;
                      }
                      await session.deleteAccount();
                      if (context.mounted) Navigator.pop(context);
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
