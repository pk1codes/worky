import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import 'admin_screen.dart';
import 'api.dart';
import 'browse_screen.dart';
import 'chrome.dart';
import 'langs.dart';
import 'language_screen.dart';
import 'local_thumb.dart' if (dart.library.io) 'local_thumb_io.dart';
import 'media_queue.dart';
import 'post_screen.dart';
import 'session.dart';
import 'talk_screen.dart';

const _kWorld = 'World';

class MineScreen extends StatefulWidget {
  const MineScreen({super.key});

  @override
  State<MineScreen> createState() => _MineScreenState();
}

class _MineScreenState extends State<MineScreen> {
  List<FeedPost> _posts = [];
  List<TalkPreview> _talks = [];
  var _loading = true;
  var _failed = false;
  String? _armedDelete;
  var _armedAccount = false;
  MediaQueue? _box;
  var _seenDrafts = 0;
  var _version = '';
  var _update = false;

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
      unawaited(_versionLine());
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

  Future<void> _versionLine() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _version = info.version);
    } catch (_) {}
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final update = await InAppUpdate.checkForUpdate();
      if (!mounted) return;
      setState(() {
        _update =
            update.updateAvailability == UpdateAvailability.updateAvailable;
      });
    } catch (_) {}
  }

  Future<void> _updateNow() async {
    try {
      await InAppUpdate.performImmediateUpdate();
    } catch (_) {}
  }

  Future<void> _load() async {
    try {
      final page = await SessionHost.of(context).api.mine();
      if (mounted) {
        setState(() {
          _posts = page.posts;
          _talks = page.talks;
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
    return DateFormat.MMMd(
      locale,
    ).add_jm().format(DateTime.fromMillisecondsSinceEpoch(at));
  }

  String? _postedPath(FeedPost post) {
    if (post.categoryPath.isEmpty) return null;
    return '$_kWorld / ${post.categoryPath.join(' / ')}';
  }

  String _talkTitle(TalkPreview talk, AppLocalizations l10n) {
    if (talk.kind == 'video' || talk.kind == 'voice' || talk.preview.isEmpty) {
      return l10n.workyTalk;
    }
    return talk.preview;
  }

  Widget _talkRow(TalkPreview talk, AppLocalizations l10n) {
    final icon = talk.kind == 'video'
        ? Icons.videocam
        : talk.kind == 'voice'
        ? Icons.mic
        : Icons.forum;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () async {
            await Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => TalkScreen(pairId: talk.id),
              ),
            );
            await _load();
          },
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                DecoratedBox(
                  decoration: const BoxDecoration(
                    color: Color(0xFFE7F2EE),
                    shape: BoxShape.circle,
                  ),
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: Icon(icon, color: const Color(0xFF0F6E56)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _talkTitle(talk, l10n),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      color: Color(0xFF16332C),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (talk.unread > 0)
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: const Color(0xFF0F6E56),
                    child: Text(
                      '${talk.unread}',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _mineAction(
    IconData icon,
    String label,
    VoidCallback onTap, {
    bool filled = false,
    Color? color,
  }) {
    return BigIcon(
      icon: icon,
      label: label,
      compact: true,
      stretch: true,
      filled: filled,
      color: color,
      onTap: onTap,
    );
  }

  Widget _cardTail(Session session, FeedPost post, AppLocalizations l10n) {
    final armed = _armedDelete == post.id;
    return Column(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFFE7F2EE),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: _mineAction(Icons.edit, l10n.edit, () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => PostScreen(edit: post),
                      ),
                    );
                    await _load();
                  }),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: _mineAction(
                    post.status == 'paused' ? Icons.play_arrow : Icons.pause,
                    post.status == 'paused' ? l10n.resume : l10n.pause,
                    () async {
                      await session.api.pause(post.id, post.status != 'paused');
                      session.dropFeed();
                      await _load();
                    },
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: _mineAction(
                    Icons.block,
                    post.contactsOpen ? l10n.block : l10n.blocked,
                    () async {
                      final blocking = post.contactsOpen;
                      try {
                        await session.api.blockIncoming(post.id, blocking);
                        if (mounted) {
                          await Speaker.say(
                            session.lang,
                            blocking ? l10n.blocked : l10n.allowed,
                          );
                        }
                        await _load();
                      } catch (_) {
                        if (mounted) {
                          await Speaker.say(session.lang, l10n.tryAgain);
                        }
                      }
                    },
                    filled: !post.contactsOpen,
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: _mineAction(
                    Icons.delete,
                    l10n.delete,
                    () async {
                      if (_armedDelete != post.id) {
                        setState(() => _armedDelete = post.id);
                        await Speaker.say(session.lang, l10n.delete);
                        return;
                      }
                      await session.api.deletePost(post.id);
                      session.dropFeed();
                      await _load();
                    },
                    filled: armed,
                    color: armed ? Colors.red : null,
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: _mineAction(Icons.share, l10n.share, () {
                    SharePlus.instance.share(
                      ShareParams(
                        text: post.posterUrl.isNotEmpty
                            ? post.posterUrl
                            : post.categoryId,
                      ),
                    );
                  }),
                ),
              ],
            ),
          ),
        ),
        for (final reach in post.reaches)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${reach.number}\n${_reachWhen(context, reach.at)}',
                    style: const TextStyle(
                      fontSize: 16,
                      color: Color(0xFF16332C),
                    ),
                  ),
                ),
                BigIcon(
                  icon: Icons.block,
                  label: reach.blocked ? l10n.blocked : l10n.block,
                  filled: reach.blocked,
                  compact: true,
                  onTap: () async {
                    final blocking = !reach.blocked;
                    try {
                      await session.api.blockNumber(reach.number, blocking);
                      if (mounted) {
                        await Speaker.say(
                          session.lang,
                          blocking ? l10n.blocked : l10n.allowed,
                        );
                      }
                      await _load();
                    } catch (_) {
                      if (mounted) {
                        await Speaker.say(session.lang, l10n.tryAgain);
                      }
                    }
                  },
                ),
              ],
            ),
          ),
      ],
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
                          color: Color(0xFF16332C),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (_version.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Row(
                          children: [
                            Text(
                              _version,
                              style: const TextStyle(
                                fontSize: 14,
                                color: Color(0xFF16332C),
                              ),
                            ),
                            if (_update) ...[
                              const SizedBox(width: 10),
                              Material(
                                color: const Color(0xFF0F6E56),
                                borderRadius: BorderRadius.circular(20),
                                child: InkWell(
                                  onTap: _updateNow,
                                  borderRadius: BorderRadius.circular(20),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    child: Text(
                                      l10n.updateAvailable,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
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
                    for (final draft in session.outbox.drafts)
                      _draft(session, draft, l10n),
                    for (final post in _posts)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: ExpandedCard(
                          post: post,
                          categoryName: _postedPath(post),
                          mine: true,
                          wide: true,
                          tail: _cardTail(session, post, l10n),
                        ),
                      ),
                    for (final talk in _talks) _talkRow(talk, l10n),
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
