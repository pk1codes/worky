import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import 'admin_screen.dart';
import 'api.dart';
import 'chrome.dart';
import 'langs.dart';
import 'language_screen.dart';
import 'local_thumb.dart' if (dart.library.io) 'local_thumb_io.dart';
import 'media_queue.dart';
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
  var _failed = false;
  String? _armedDelete;
  var _armedAccount = false;
  MediaQueue? _box;
  var _seenDrafts = 0;

  @override
  void initState() {
    super.initState();
    FirebaseAnalytics.instance.logScreenView(screenName: 'mine');
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final session = SessionHost.of(context);
      _box = session.outbox;
      _seenDrafts = _box!.drafts.length;
      _box!.addListener(_onBox);
      unawaited(Speaker.say(session.lang, AppLocalizations.of(context).mine));
      await _load();
    });
  }

  void _onBox() {
    final box = _box;
    if (!mounted || box == null) return;
    final n = box.drafts.length;
    if (n < _seenDrafts) unawaited(_load());
    _seenDrafts = n;
    setState(() {});
  }

  @override
  void dispose() {
    _box?.removeListener(_onBox);
    super.dispose();
  }

  Widget _draft(Session session, OutboxDraft draft, AppLocalizations l10n) {
    final jobs = <MediaJob>[
      for (final id in draft.jobIds) ?session.outbox.job(id),
    ];
    MediaJob? image;
    for (final item in jobs) {
      if (item.kind == 'image') {
        image = item;
        break;
      }
    }
    final failed = draft.failed || jobs.any((item) => item.status == 'failed');
    final busy =
        !failed && (jobs.isEmpty || jobs.any((item) => item.status != 'ready'));
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          if (image != null)
            LocalThumb(path: image.path, height: 180, width: double.infinity)
          else
            const SizedBox(
              height: 180,
              width: double.infinity,
              child: ColoredBox(color: Color(0xFFE7F2EE)),
            ),
          if (busy) const LinearProgressIndicator(),
          if (failed)
            Padding(
              padding: const EdgeInsets.all(8),
              child: BigIcon(
                icon: Icons.refresh,
                label: l10n.tryAgain,
                onTap: () => session.outbox.retryDraft(draft.id),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _load() async {
    try {
      final posts = await SessionHost.of(context).api.mine();
      if (mounted) {
        setState(() {
          _posts = posts;
          _loading = false;
          _failed = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = _posts.isEmpty;
        });
      }
    }
  }

  String _reachWhen(BuildContext context, int at) {
    if (at <= 0) return '';
    final locale = Localizations.localeOf(context).toString();
    return DateFormat.MMMd(locale).add_jm().format(
      DateTime.fromMillisecondsSinceEpoch(at),
    );
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
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    BigIcon(
                      icon: Icons.arrow_back,
                      label: l10n.back,
                      compact: true,
                      onTap: () => Navigator.pop(context),
                    ),
                    const Spacer(),
                    BigIcon(
                      icon: Icons.translate,
                      label: kAutonym[session.lang] ?? session.lang,
                      compact: true,
                      onTap: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                const LanguageScreen(popOnPick: true),
                          ),
                        );
                        if (mounted) setState(() {});
                      },
                    ),
                    if (session.admin)
                      BigIcon(
                        icon: Icons.category,
                        label: l10n.admin,
                        compact: true,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const AdminScreen(),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 12),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                      child: Text(
                        l10n.mine,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    for (final draft in session.outbox.drafts)
                      _draft(session, draft, l10n),
                    if (_loading) const LinearProgressIndicator(),
                    if (_failed && _posts.isEmpty)
                      BigIcon(
                        icon: Icons.refresh,
                        label: l10n.tryAgain,
                        onTap: () {
                          setState(() {
                            _loading = true;
                            _failed = false;
                          });
                          _load();
                        },
                      )
                    else if (!_loading &&
                        _posts.isEmpty &&
                        session.outbox.drafts.isEmpty)
                      BigIcon(
                        icon: Icons.add_a_photo,
                        label: l10n.post,
                        filled: true,
                        onTap: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const PostScreen(),
                            ),
                          );
                          await _load();
                        },
                      ),
                    for (final post in _posts)
                      Card(
                        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            NetImage(
                              url: post.posterUrl,
                              height: 180,
                              width: double.infinity,
                              cacheLogical: MediaQuery.sizeOf(context).width,
                              error: const SizedBox(height: 80),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(8),
                              child: Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  BigIcon(
                                    icon: Icons.edit,
                                    label: l10n.edit,
                                    onTap: () async {
                                      await Navigator.of(context).push(
                                        MaterialPageRoute<void>(
                                          builder: (_) =>
                                              PostScreen(edit: post),
                                        ),
                                      );
                                      await _load();
                                    },
                                  ),
                                  BigIcon(
                                    icon: post.status == 'paused'
                                        ? Icons.play_arrow
                                        : Icons.pause,
                                    label: post.status == 'paused'
                                        ? l10n.resume
                                        : l10n.pause,
                                    onTap: () async {
                                      await session.api.pause(
                                        post.id,
                                        post.status != 'paused',
                                      );
                                      session.dropFeed();
                                      await _load();
                                    },
                                  ),
                                  BigIcon(
                                    icon: Icons.block,
                                    label: post.contactsOpen
                                        ? l10n.block
                                        : l10n.blocked,
                                    filled: !post.contactsOpen,
                                    onTap: () async {
                                      final blocking = post.contactsOpen;
                                      try {
                                        await session.api.blockIncoming(
                                          post.id,
                                          blocking,
                                        );
                                        if (mounted) {
                                          await Speaker.say(
                                            session.lang,
                                            blocking
                                                ? l10n.blocked
                                                : l10n.allowed,
                                          );
                                        }
                                        await _load();
                                      } catch (_) {
                                        if (mounted) {
                                          await Speaker.say(
                                            session.lang,
                                            l10n.tryAgain,
                                          );
                                        }
                                      }
                                    },
                                  ),
                                  BigIcon(
                                    icon: Icons.delete,
                                    label: l10n.delete,
                                    filled: _armedDelete == post.id,
                                    color: _armedDelete == post.id
                                        ? Colors.red
                                        : null,
                                    onTap: () async {
                                      if (_armedDelete != post.id) {
                                        setState(() => _armedDelete = post.id);
                                        await Speaker.say(
                                          session.lang,
                                          l10n.delete,
                                        );
                                        return;
                                      }
                                      await session.api.deletePost(post.id);
                                      session.dropFeed();
                                      await _load();
                                    },
                                  ),
                                  BigIcon(
                                    icon: Icons.share,
                                    label: l10n.share,
                                    onTap: () => SharePlus.instance.share(
                                      ShareParams(
                                        text: post.posterUrl.isNotEmpty
                                            ? post.posterUrl
                                            : post.categoryId,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            for (final reach in post.reaches)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '${reach.number}\n${_reachWhen(context, reach.at)}',
                                        style: const TextStyle(fontSize: 16),
                                      ),
                                    ),
                                    BigIcon(
                                      icon: Icons.block,
                                      label: reach.blocked
                                          ? l10n.blocked
                                          : l10n.block,
                                      filled: reach.blocked,
                                      onTap: () async {
                                        final blocking = !reach.blocked;
                                        try {
                                          await session.api.blockNumber(
                                            reach.number,
                                            blocking,
                                          );
                                          if (mounted) {
                                            await Speaker.say(
                                              session.lang,
                                              blocking
                                                  ? l10n.blocked
                                                  : l10n.allowed,
                                            );
                                          }
                                          await _load();
                                        } catch (_) {
                                          if (mounted) {
                                            await Speaker.say(
                                              session.lang,
                                              l10n.tryAgain,
                                            );
                                          }
                                        }
                                      },
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
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
                    icon: Icons.description,
                    label: l10n.terms,
                    onTap: () => Speaker.say(
                      session.lang,
                      '${l10n.termsBody} ${l10n.contactNotice}',
                    ),
                  ),
                  BigIcon(
                    icon: Icons.mail_outline,
                    label: l10n.contact,
                    onTap: () => launchUrl(Uri.parse('mailto:$kSupportEmail')),
                  ),
                  BigIcon(
                    icon: Icons.person_off,
                    label: l10n.deleteAccount,
                    filled: _armedAccount,
                    color: Colors.red,
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
