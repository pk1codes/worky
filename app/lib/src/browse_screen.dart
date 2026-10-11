import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../l10n/app_localizations.dart';
import 'api.dart';
import 'chrome.dart';
import 'langs.dart';
import 'mine_screen.dart';
import 'post_screen.dart';
import 'session.dart';
import 'talk_push.dart';
import 'talk_screen.dart';

class BrowseScreen extends StatefulWidget {
  const BrowseScreen({this.picking = false, this.onPicked, super.key});

  final bool picking;
  final ValueChanged<String>? onPicked;

  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> {
  final List<String> _parents = [''];
  List<FeedCategory> _rows = [];
  var _loading = true;
  var _map = false;
  String? _pinId;
  String? _openId;
  var _failed = false;

  @override
  void initState() {
    super.initState();
    FirebaseAnalytics.instance.logScreenView(screenName: 'browse');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final session = SessionHost.of(context);
      final l10n = AppLocalizations.of(context);
      unawaited(Speaker.say(session.lang, l10n.near));
      unawaited(_load());
      TalkPush.flush();
    });
  }

  void _paintCached(Session session) {
    final cached = session.feedCache[session.cacheKey(_parents.last)];
    if (cached != null) {
      _rows = cached;
      _loading = false;
    } else {
      _loading = true;
    }
  }

  Future<void> _load({bool force = false}) async {
    final session = SessionHost.of(context);
    if (session.lat == null) {
      final ok = await session.locate();
      if (!ok && mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
        return;
      }
    }
    final parent = _parents.last;
    final key = session.cacheKey(parent);
    final cached = session.feedCache[key];
    if (cached != null && mounted) {
      setState(() {
        _rows = cached;
        _loading = false;
        _failed = false;
      });
      if (!force && session.feedIsFresh(key)) return;
    }
    try {
      final fresh = await session.api.feed(
        parentId: parent,
        lat: session.lat!,
        lng: session.lng!,
        lang: session.lang ?? 'en',
        headersOnly: widget.picking,
      );
      if (!mounted) return;
      if (fresh == null) {
        setState(() => _loading = false);
        return;
      }
      if (!widget.picking) session.rememberFeed(key, fresh);
      setState(() {
        _rows = fresh;
        _loading = false;
        _failed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = _rows.isEmpty;
      });
      await Speaker.say(session.lang, AppLocalizations.of(context).tryAgain);
    }
  }

  void _drill(String id) {
    final session = SessionHost.of(context);
    setState(() {
      _parents.add(id);
      _pinId = null;
      _openId = null;
      _paintCached(session);
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final session = SessionHost.of(context);
    final posts = [for (final row in _rows) ...row.posts];
    return Paged(
      page: _map ? 7 : 4,
      child: Scaffold(
        floatingActionButton: widget.picking
            ? null
            : FloatingActionButton.extended(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const PostScreen()),
                  );
                },
                icon: const Icon(Icons.add_a_photo),
                label: Text(l10n.post),
              ),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    if (_parents.length > 1 || widget.picking)
                      BigIcon(
                        icon: Icons.arrow_back,
                        label: l10n.back,
                        compact: true,
                        onTap: () {
                          if (_parents.length > 1) {
                            final session = SessionHost.of(context);
                            setState(() {
                              _parents.removeLast();
                              _pinId = null;
                              _openId = null;
                              _paintCached(session);
                            });
                            _load();
                          } else {
                            Navigator.pop(context);
                          }
                        },
                      ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Image(
                        image: AssetImage('assets/worky.png'),
                        height: 40,
                        fit: BoxFit.contain,
                        semanticLabel: 'Worky',
                      ),
                    ),
                    const Spacer(),
                    if (!widget.picking)
                      BigIcon(
                        icon: _map ? Icons.view_agenda : Icons.map,
                        label: l10n.map,
                        compact: true,
                        onTap: () => setState(() => _map = !_map),
                      ),
                    if (!widget.picking)
                      BigIcon(
                        icon: Icons.person,
                        label: l10n.mine,
                        compact: true,
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const MineScreen(),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
              if (_failed)
                BigIcon(
                  icon: Icons.refresh,
                  label: l10n.tryAgain,
                  onTap: () {
                    setState(() => _loading = _rows.isEmpty);
                    _load(force: true);
                  },
                ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _map
                    ? _MapPane(
                        posts: posts,
                        lat: session.lat ?? 20.5,
                        lng: session.lng ?? 78.9,
                        showHere: session.lat != null && session.lng != null,
                        pinId: _pinId,
                        openId: _openId,
                        nameFor: _nameFor,
                        onPin: _showPin,
                        onOpen: (id) =>
                            setState(() => _openId = _openId == id ? null : id),
                        onClose: () => setState(() {
                          _pinId = null;
                          _openId = null;
                        }),
                      )
                    : RefreshIndicator(
                        onRefresh: () => _load(force: true),
                        child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          children: [
                            for (final row in _rows)
                              _CategoryRow(
                                row: row,
                                picking: widget.picking,
                                openId: _openId,
                                onDrill: () => _drill(row.id),
                                onPick: () => widget.onPicked?.call(row.id),
                                onOpen: (id) => setState(
                                  () => _openId = _openId == id ? null : id,
                                ),
                              ),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPin(String id) {
    final posts = [for (final row in _rows) ...row.posts];
    final next = _postById(posts, id);
    final current = _postById(posts, _pinId);
    if (next == null) return;
    if (current != null &&
        pinCell(current.lat, current.lng) == pinCell(next.lat, next.lng)) {
      return;
    }
    setState(() {
      _pinId = id;
      _openId = null;
    });
  }

  FeedPost? _postById(List<FeedPost> posts, String? id) {
    if (id == null) return null;
    for (final post in posts) {
      if (post.id == id) return post;
    }
    return null;
  }

  String? _nameFor(FeedPost? post) {
    if (post == null) return null;
    for (final row in _rows) {
      if (row.posts.any((item) => item.id == post.id)) return row.name;
    }
    return null;
  }
}

const _collapsedPoster = 150.0;
const _stripGap = 12.0;
const _stripPad = 12.0;
const _openInnerWidth = 280.0;
const _openInnerPad = 8.0;
const _openOuterWidth = _openInnerWidth + _openInnerPad * 2;

const _rowIcons = <String, IconData>{
  'cook': Icons.soup_kitchen,
  'car-driver': Icons.directions_car,
  'house-maid': Icons.cleaning_services,
  'security-guard': Icons.shield,
  'delivery-driver': Icons.delivery_dining,
  'sales-man': Icons.storefront,
  'car-cleaner': Icons.local_car_wash,
  'loader': Icons.inventory_2,
  'oil-field-rigs': Icons.oil_barrel,
  'hospital': Icons.local_hospital,
  'asst-driller': Icons.hardware,
  'driller': Icons.construction,
  'medic': Icons.medical_services,
  'service-companies': Icons.handyman,
  'oil-company-jobs': Icons.apartment,
};

IconData _rowIcon(FeedCategory row) {
  return _rowIcons[row.id] ?? (row.isJob ? Icons.badge : Icons.folder);
}

(int, int) pinCell(double lat, double lng) =>
    ((lat * 50).round(), (lng * 50).round());

double stripRevealOffset({
  required int index,
  required double pixels,
  required double viewport,
  required double maxExtent,
}) {
  const inset = 12.0;
  final start = _stripPad + index * (_collapsedPoster + _stripGap);
  final end = start + _openOuterWidth;
  if (viewport <= 0 || (start >= pixels && end <= pixels + viewport)) {
    return pixels;
  }
  final room = viewport - _openOuterWidth;
  final margin = room >= inset ? inset : (room > 0 ? room : 0.0);
  var target = end + margin - viewport;
  if (start < target) target = start;
  if (target < 0) target = 0;
  if (target > maxExtent) target = maxExtent;
  return target;
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.row,
    required this.picking,
    required this.openId,
    required this.onDrill,
    required this.onPick,
    required this.onOpen,
  });

  final FeedCategory row;
  final bool picking;
  final String? openId;
  final VoidCallback onDrill;
  final VoidCallback onPick;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final job = row.isJob;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () {
                    Speaker.say(SessionHost.of(context).lang, row.name);
                    if (!job) {
                      onDrill();
                    } else if (picking) {
                      onPick();
                    }
                  },
                  child: Row(
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: const BoxDecoration(
                          color: Color(0xFFE7F2EE),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _rowIcon(row),
                          color: const Color(0xFF0F6E56),
                          size: 36,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          row.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 20,
                            color: Color(0xFF16332C),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (!job)
                        const Icon(
                          Icons.chevron_right,
                          size: 28,
                          color: Color(0xFF16332C),
                        )
                      else if (picking)
                        const Icon(
                          Icons.arrow_forward,
                          size: 28,
                          color: Color(0xFF16332C),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (job && !picking)
            SizedBox(
              height:
                  openId != null && row.posts.any((post) => post.id == openId)
                  ? 560
                  : 210,
              child: _JobStrip(
                posts: row.posts,
                categoryName: row.name,
                openId: openId,
                onOpen: onOpen,
              ),
            ),
        ],
      ),
    );
  }
}

class _JobStrip extends StatefulWidget {
  const _JobStrip({
    required this.posts,
    required this.categoryName,
    required this.openId,
    required this.onOpen,
    this.nameOf,
    this.scrollOpen = false,
  });

  final List<FeedPost> posts;
  final String categoryName;
  final String? Function(FeedPost post)? nameOf;
  final String? openId;
  final ValueChanged<String> onOpen;
  final bool scrollOpen;

  @override
  State<_JobStrip> createState() => _JobStripState();
}

class _JobStripState extends State<_JobStrip> {
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scheduleReveal();
  }

  @override
  void didUpdateWidget(_JobStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.openId != oldWidget.openId) _scheduleReveal();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _scheduleReveal() {
    final id = widget.openId;
    if (id == null || !widget.posts.any((post) => post.id == id)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final index = widget.posts.indexWhere((post) => post.id == widget.openId);
      if (index < 0) return;
      final position = _scroll.position;
      final target = stripRevealOffset(
        index: index,
        pixels: position.pixels,
        viewport: position.viewportDimension,
        maxExtent: position.maxScrollExtent,
      );
      if ((target - position.pixels).abs() < 1) return;
      _scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final openId = widget.openId;
    return ListView.separated(
      controller: _scroll,
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(_stripPad),
      itemCount: widget.posts.length,
      separatorBuilder: (_, _) => const SizedBox(width: _stripGap),
      itemBuilder: (context, index) {
        final post = widget.posts[index];
        final open = post.id == openId;
        final name = widget.nameOf?.call(post) ?? widget.categoryName;
        return GestureDetector(
          onTap: () => widget.onOpen(post.id),
          child: open
              ? widget.scrollOpen
                    ? SizedBox(
                        width: _openOuterWidth,
                        child: SingleChildScrollView(
                          child: ExpandedCard(post: post, categoryName: name),
                        ),
                      )
                    : Align(
                        alignment: Alignment.topCenter,
                        widthFactor: 1,
                        child: ExpandedCard(post: post, categoryName: name),
                      )
              : Align(
                  alignment: Alignment.topCenter,
                  widthFactor: 1,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: NetImage(
                      url: post.thumbUrl.isEmpty
                          ? post.posterUrl
                          : post.thumbUrl,
                      width: _collapsedPoster,
                      height: 190,
                      cacheLogical: _collapsedPoster,
                      error: const SizedBox(
                        width: _collapsedPoster,
                        height: 190,
                        child: ColoredBox(color: Color(0xFFE7F2EE)),
                      ),
                    ),
                  ),
                ),
        );
      },
    );
  }
}

class ExpandedCard extends StatefulWidget {
  const ExpandedCard({
    required this.post,
    this.categoryName,
    this.mine = false,
    this.wide = false,
    super.key,
  });

  final FeedPost post;
  final String? categoryName;
  final bool mine;
  final bool wide;

  @override
  State<ExpandedCard> createState() => _ExpandedCardState();
}

class _ExpandedCardState extends State<ExpandedCard> {
  List<MediaItem> _media = [];
  VideoPlayerController? _video;
  String? _playingUrl;
  bool _showPause = false;
  int _playToken = 0;
  bool _ready = false;
  Future<List<MediaItem>>? _detail;
  String? _reachNote;
  final AudioPlayer _audio = AudioPlayer();
  final PageController _pages = PageController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    unawaited(_ensureMedia().catchError((Object _) => <MediaItem>[]));
    if (!widget.mine) _reachNote ??= _composeNote();
  }

  Future<List<MediaItem>> _ensureMedia() {
    return _detail ??= _fetch();
  }

  Future<List<MediaItem>> _fetch() async {
    final api = SessionHost.of(context).api;
    try {
      final detail = await api.post(widget.post.id);
      if (!mounted) return detail.media;
      setState(() {
        _media = detail.media;
        _ready = true;
      });
      return detail.media;
    } catch (_) {
      _detail = null;
      rethrow;
    }
  }

  @override
  void dispose() {
    _pages.dispose();
    _video?.dispose();
    unawaited(_audio.dispose());
    super.dispose();
  }

  Future<void> _playAudio(String url) async {
    await _audio.stop();
    await _audio.play(UrlSource(url));
  }

  Future<void> _play(String url) async {
    final token = ++_playToken;
    final previous = _video;
    _video = null;
    _playingUrl = null;
    if (mounted) setState(() => _showPause = false);
    await previous?.dispose();
    if (!mounted || token != _playToken) return;
    final controller = VideoPlayerController.networkUrl(Uri.parse(url));
    try {
      await controller.initialize();
      await controller.setLooping(false);
      _watch(controller);
      await controller.play();
    } catch (_) {
      await controller.dispose();
      if (!mounted || token != _playToken) return;
      final session = SessionHost.of(context);
      await Speaker.say(session.lang, AppLocalizations.of(context).tryAgain);
      return;
    }
    if (!mounted || token != _playToken) {
      await controller.dispose();
      return;
    }
    setState(() {
      _video = controller;
      _playingUrl = url;
      _showPause = true;
    });
  }

  void _watch(VideoPlayerController controller) {
    controller.addListener(() {
      if (!mounted || _video != controller) return;
      final value = controller.value;
      if (!value.isInitialized) return;
      final showPause = value.isPlaying;
      if (showPause == _showPause) return;
      setState(() => _showPause = showPause);
    });
  }

  bool _ended(VideoPlayerController controller) {
    final value = controller.value;
    return value.isInitialized &&
        value.duration > Duration.zero &&
        value.position >= value.duration &&
        !value.isPlaying;
  }

  Future<void> _toggle(String url) async {
    final controller = _video;
    if (controller == null ||
        _playingUrl != url ||
        !controller.value.isInitialized) {
      await _play(url);
      return;
    }
    if (controller.value.isPlaying) {
      await controller.pause();
      return;
    }
    if (_ended(controller)) await controller.seekTo(Duration.zero);
    await controller.play();
  }

  Future<void> _onPlayTap(String? url) async {
    if (_showPause) {
      await _video?.pause();
      return;
    }
    if (url == null) {
      await _openVideo();
      return;
    }
    if (_pages.hasClients) {
      await _pages.animateToPage(
        1,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
    await _toggle(url);
  }

  Future<void> _openVideo() async {
    final hadPage = _media.any((item) => item.kind == 'video');
    List<MediaItem> media;
    try {
      media = await _ensureMedia();
    } catch (_) {
      if (!mounted) return;
      final session = SessionHost.of(context);
      await Speaker.say(session.lang, AppLocalizations.of(context).tryAgain);
      return;
    }
    if (!mounted) return;
    final videos = media.where((item) => item.kind == 'video').toList();
    if (videos.isEmpty) return;
    final url = videos.first.url;
    void start() {
      if (!mounted) return;
      _pages.animateToPage(
        1,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
      unawaited(_toggle(url));
    }

    if (hadPage) {
      start();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => start());
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final videos = _media.where((item) => item.kind == 'video').toList();
    final wide = widget.wide;
    final cacheWidth = wide ? 360 : 280;
    return Padding(
      padding: EdgeInsets.all(wide ? 12 : 0),
      child: Material(
        color: Colors.white,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFE7F2EE)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(_openInnerPad),
          child: SizedBox(
            width: wide ? double.infinity : _openInnerWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: wide ? 16 : 0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(wide ? 16 : 0),
                    child: SizedBox(
                      height: wide ? 220 : 320,
                      child: PageView(
                        controller: _pages,
                        children: [
                          Stack(
                            fit: StackFit.expand,
                            children: [
                              KeyedSubtree(
                                key: const ValueKey('poster'),
                                child: _poster(cacheWidth),
                              ),
                              if (videos.isNotEmpty ||
                                  (widget.post.hasVideo && !_ready))
                                _videoButton(
                                  () => _onPlayTap(
                                    videos.isEmpty ? null : videos.first.url,
                                  ),
                                ),
                            ],
                          ),
                          for (final item in videos) _videoPage(item),
                        ],
                      ),
                    ),
                  ),
                ),
                for (final item in _media.where((item) => item.kind == 'audio'))
                  BigIcon(
                    icon: Icons.graphic_eq,
                    onTap: () => _playAudio(item.url),
                  ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: wide ? 16 : 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if ((widget.categoryName ?? '').isNotEmpty) ...[
                        Text(
                          widget.categoryName!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 20,
                            color: Color(0xFF16332C),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0xFFE7F2EE),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _fact(Icons.calendar_today, _when(context)),
                              const SizedBox(height: 4),
                              _fact(
                                widget.post.band == 'near'
                                    ? Icons.place
                                    : widget.post.band == 'mid'
                                    ? Icons.directions_walk
                                    : Icons.public,
                                widget.post.km == null
                                    ? _bandLabel(l10n)
                                    : '${widget.post.km} km',
                              ),
                              if (widget.post.langs.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                _fact(
                                  Icons.translate,
                                  '${l10n.speaks} ${widget.post.langs.map((code) => kAutonym[code] ?? code).join(' · ')}',
                                  maxLines: null,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (!widget.mine)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: BigIcon(
                            icon: Icons.forum,
                            label: l10n.workyTalk,
                            filled: true,
                            compact: true,
                            stretch: true,
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    TalkScreen(postId: widget.post.id),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: BigIcon(
                            icon: Icons.chat,
                            label: 'WhatsApp',
                            filled: true,
                            compact: true,
                            stretch: true,
                            color: const Color(0xFF25D366),
                            onTap: () => _open('whatsapp'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: BigIcon(
                            icon: Icons.call,
                            label: l10n.call,
                            filled: true,
                            compact: true,
                            stretch: true,
                            color: const Color(0xFF1A73E8),
                            onTap: () => _open('phone'),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _fact(IconData icon, String text, {int? maxLines = 1}) {
    return Row(
      crossAxisAlignment: maxLines == 1
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 22, color: const Color(0xFF0F6E56)),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            maxLines: maxLines,
            overflow: maxLines == null
                ? TextOverflow.visible
                : TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 16,
              color: Color(0xFF16332C),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  String _when(BuildContext context) {
    final ms = widget.post.createdAt;
    if (ms == null) return '${widget.post.daysAgo}';
    final locale = Localizations.localeOf(context).toString();
    return DateFormat.yMMMd(
      locale,
    ).format(DateTime.fromMillisecondsSinceEpoch(ms));
  }

  String _bandLabel(AppLocalizations l10n) {
    if (widget.post.band == 'near') return l10n.near;
    if (widget.post.band == 'mid') return l10n.mid;
    return l10n.far;
  }

  Widget _poster(int cacheWidth) {
    final poster = widget.post.posterUrl;
    if (poster.isEmpty) return const ColoredBox(color: Color(0xFFE7F2EE));
    return NetImage(
      url: poster,
      fit: BoxFit.cover,
      cacheLogical: cacheWidth.toDouble(),
    );
  }

  Widget _videoButton(VoidCallback onTap) {
    return Align(
      alignment: Alignment.bottomLeft,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: BigIcon(
          icon: _showPause ? Icons.pause : Icons.play_arrow,
          filled: true,
          onTap: onTap,
        ),
      ),
    );
  }

  Widget _videoPage(MediaItem item) {
    final ready = _video != null && _playingUrl == item.url;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (ready) VideoPlayer(_video!) else _poster(widget.wide ? 360 : 280),
        _videoButton(() => _onPlayTap(item.url)),
      ],
    );
  }

  String _composeNote() {
    final session = SessionHost.of(context);
    final line = AppLocalizations.of(context).reachNote;
    final lat = session.lat;
    final lng = session.lng;
    if (lat == null || lng == null) return line;
    final place =
        'https://maps.google.com/?q=${lat.toStringAsFixed(5)},${lng.toStringAsFixed(5)}';
    return '$line\n$place';
  }

  Future<void> _open(String channel) async {
    final session = SessionHost.of(context);
    final retry = AppLocalizations.of(context).tryAgain;
    try {
      final url = await session.api.reveal(widget.post.id, channel);
      if (!mounted) return;
      final opened = channel == 'whatsapp'
          ? await _openWhatsApp(_digits(url))
          : await launchUrl(
              Uri.parse(url),
              mode: LaunchMode.externalApplication,
            );
      if (!opened && mounted) await Speaker.say(session.lang, retry);
    } catch (_) {
      if (mounted) await Speaker.say(session.lang, retry);
    }
  }

  String _digits(String url) {
    final parts = Uri.parse(url).pathSegments.where((part) => part.isNotEmpty);
    final number = parts.isEmpty ? '' : parts.last;
    if (!RegExp(r'^\d{8,15}$').hasMatch(number)) {
      throw const FormatException('number');
    }
    return number;
  }

  Future<bool> _openWhatsApp(String digits) async {
    final note = _reachNote ?? _composeNote();
    final app = Uri.parse(
      'whatsapp://send?phone=$digits&text=${Uri.encodeComponent(note)}',
    );
    try {
      if (await launchUrl(
        app,
        mode: LaunchMode.externalNonBrowserApplication,
      )) {
        return true;
      }
    } catch (_) {}
    try {
      return await launchUrl(
        Uri.parse('https://wa.me/$digits?text=${Uri.encodeComponent(note)}'),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      return false;
    }
  }
}

class _MapPane extends StatefulWidget {
  const _MapPane({
    required this.posts,
    required this.lat,
    required this.lng,
    required this.showHere,
    required this.pinId,
    required this.openId,
    required this.nameFor,
    required this.onPin,
    required this.onOpen,
    required this.onClose,
  });

  final List<FeedPost> posts;
  final double lat;
  final double lng;
  final bool showHere;
  final String? pinId;
  final String? openId;
  final String? Function(FeedPost post) nameFor;
  final ValueChanged<String> onPin;
  final ValueChanged<String> onOpen;
  final VoidCallback onClose;

  @override
  State<_MapPane> createState() => _MapPaneState();
}

class _MapPaneState extends State<_MapPane> {
  MapLibreMapController? _controller;

  static const _zoom = 17.0;
  static const _control = 40.0;
  static const _gap = 4.0;
  static const _padClear = 12.0;
  static const _sideClear = _control * 3 + _gap * 2 + 16;

  Future<void> _center() async {
    final controller = _controller;
    if (controller == null) return;
    final points = <LatLng>[
      LatLng(widget.lat, widget.lng),
      for (final post in widget.posts) LatLng(post.lat, post.lng),
    ];
    try {
      if (_onePlace(points)) {
        await controller.animateCamera(
          CameraUpdate.newLatLngZoom(_abovePad(points.first), _zoom),
          duration: const Duration(milliseconds: 350),
        );
        return;
      }
      var minLat = points.first.latitude;
      var maxLat = minLat;
      var minLng = points.first.longitude;
      var maxLng = minLng;
      for (final point in points) {
        minLat = math.min(minLat, point.latitude);
        maxLat = math.max(maxLat, point.latitude);
        minLng = math.min(minLng, point.longitude);
        maxLng = math.max(maxLng, point.longitude);
      }
      await controller.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(minLat, minLng),
            northeast: LatLng(maxLat, maxLng),
          ),
          left: 24,
          top: 24,
          right: _sideClear,
          bottom: _padClear,
        ),
        duration: const Duration(milliseconds: 350),
      );
    } catch (_) {}
  }

  bool _onePlace(List<LatLng> points) {
    final first = points.first;
    for (final point in points.skip(1)) {
      if ((point.latitude - first.latitude).abs() > 0.02) return false;
      if ((point.longitude - first.longitude).abs() > 0.02) return false;
    }
    return true;
  }

  LatLng _abovePad(LatLng point) {
    final metersPerPixel =
        156543.03392 *
        math.cos(point.latitude * math.pi / 180) /
        math.pow(2, _zoom);
    final south = (_padClear / 2) * metersPerPixel / 111320;
    return LatLng(point.latitude - south, point.longitude);
  }

  Future<void> _nudge(double dx, double dy) async {
    final controller = _controller;
    if (controller == null) return;
    try {
      await controller.animateCamera(
        CameraUpdate.scrollBy(dx, dy),
        duration: const Duration(milliseconds: 250),
      );
    } catch (_) {}
  }

  Future<void> _stepZoom(double amount) async {
    final controller = _controller;
    if (controller == null) return;
    try {
      await controller.animateCamera(
        CameraUpdate.zoomBy(amount),
        duration: const Duration(milliseconds: 250),
      );
    } catch (_) {}
  }

  void _openNearest(LatLng tap) {
    final zoom = _controller?.cameraPosition?.zoom ?? _zoom;
    final metersPerPixel =
        156543.03392 * math.cos(widget.lat * math.pi / 180) / math.pow(2, zoom);
    final slopKm = metersPerPixel * 40 / 1000;
    FeedPost? best;
    var bestKm = slopKm;
    for (final post in widget.posts) {
      final km = _km(tap.latitude, tap.longitude, post.lat, post.lng);
      if (km <= bestKm) {
        bestKm = km;
        best = post;
      }
    }
    if (best != null) widget.onPin(best.id);
  }

  double _km(double aLat, double aLng, double bLat, double bLng) {
    const r = 6371.0;
    final dLat = (bLat - aLat) * math.pi / 180;
    final dLng = (bLng - aLng) * math.pi / 180;
    final s =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(aLat * math.pi / 180) *
            math.cos(bLat * math.pi / 180) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return 2 * r * math.asin(math.min(1, math.sqrt(s)));
  }

  Future<void> _draw() async {
    final controller = _controller;
    if (controller == null) return;
    try {
      await controller.clearCircles();
      if (widget.showHere) {
        await controller.addCircle(
          CircleOptions(
            geometry: LatLng(widget.lat, widget.lng),
            circleColor: '#16332C',
            circleRadius: 8,
          ),
        );
      }
      final counts = <(int, int), int>{};
      for (final post in widget.posts) {
        final cell = pinCell(post.lat, post.lng);
        counts[cell] = (counts[cell] ?? 0) + 1;
      }
      final drawn = <(int, int)>{};
      for (final post in widget.posts) {
        final cell = pinCell(post.lat, post.lng);
        if (!drawn.add(cell)) continue;
        final cluster = (counts[cell] ?? 0) > 1;
        await controller.addCircle(
          CircleOptions(
            geometry: LatLng(post.lat, post.lng),
            circleColor: '#0F6E56',
            circleRadius: cluster ? 22 : 14,
            circleStrokeWidth: cluster ? 6 : 0,
            circleStrokeColor: '#E7F2EE',
          ),
          {'postId': post.id},
        );
      }
    } catch (_) {}
  }

  Future<void> _onStyle() async {
    await _center();
    await _draw();
  }

  @override
  void didUpdateWidget(covariant _MapPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    final moved = oldWidget.lat != widget.lat || oldWidget.lng != widget.lng;
    final postsChanged = !_samePosts(oldWidget.posts, widget.posts);
    if (moved || postsChanged) {
      _center();
      _draw();
    }
    final wasOpen = _listed(oldWidget.posts, oldWidget.pinId);
    final isOpen = _listed(widget.posts, widget.pinId);
    if (wasOpen != isOpen || oldWidget.openId != widget.openId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _controller?.forceResizeWebMap();
      });
    }
  }

  bool _listed(List<FeedPost> posts, String? id) {
    if (id == null) return false;
    for (final post in posts) {
      if (post.id == id) return true;
    }
    return false;
  }

  bool _samePosts(List<FeedPost> a, List<FeedPost> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id) return false;
    }
    return true;
  }

  FeedPost? _pinPost() {
    final id = widget.pinId;
    if (id == null) return null;
    for (final post in widget.posts) {
      if (post.id == id) return post;
    }
    return null;
  }

  List<FeedPost> _cellPosts(FeedPost pin) {
    final cell = pinCell(pin.lat, pin.lng);
    return [
      for (final post in widget.posts)
        if (pinCell(post.lat, post.lng) == cell) post,
    ];
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final pin = _pinPost();
        final cell = pin == null ? const <FeedPost>[] : _cellPosts(pin);
        final expanded =
            widget.openId != null &&
            cell.any((post) => post.id == widget.openId);
        final cap = math.max(0.0, constraints.maxHeight - _padClear);
        final wanted = 48.0 + (expanded ? 560.0 : 210.0);
        final sheetHeight = math.min(wanted, cap);
        final showSheet = pin != null && cell.isNotEmpty && sheetHeight >= 48;
        return Column(
          children: [
            Expanded(child: _map()),
            if (showSheet)
              SizedBox(
                height: sheetHeight,
                child: Material(
                  color: Colors.white,
                  elevation: 12,
                  shadowColor: const Color(0x291C2421),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      SizedBox(
                        height: 48,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                              width: 48,
                              height: 6,
                              decoration: BoxDecoration(
                                color: const Color(0xFFE5E0D5),
                                borderRadius: BorderRadius.circular(99),
                              ),
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: IconButton(
                                onPressed: widget.onClose,
                                icon: const Icon(Icons.close),
                                style: IconButton.styleFrom(
                                  backgroundColor: const Color(0xFFF4F2EB),
                                  foregroundColor: const Color(0xFF1C2421),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: _JobStrip(
                          posts: cell,
                          categoryName: '',
                          nameOf: widget.nameFor,
                          openId: expanded ? widget.openId : null,
                          scrollOpen: expanded && cap < 608,
                          onOpen: widget.onOpen,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _map() {
    return Stack(
      children: [
        MapLibreMap(
          styleString: 'https://tiles.openfreemap.org/styles/liberty',
          initialCameraPosition: CameraPosition(
            target: _abovePad(LatLng(widget.lat, widget.lng)),
            zoom: _zoom,
          ),
          onMapCreated: (controller) {
            _controller = controller;
            controller.onCircleTapped.add((circle) {
              final id = circle.data?['postId'];
              if (id is String) widget.onPin(id);
            });
          },
          featureTapsTriggersMapClick: true,
          onMapClick: (_, latLng) => _openNearest(latLng),
          onStyleLoadedCallback: _onStyle,
          myLocationEnabled: false,
          compassEnabled: false,
          rotateGesturesEnabled: false,
          tiltGesturesEnabled: false,
        ),
        Positioned(right: 8, bottom: 8, child: _controls()),
      ],
    );
  }

  Widget _controls() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _controlButton(Icons.arrow_upward, () {
          _nudge(0, -160);
        }),
        const SizedBox(height: _gap),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _controlButton(Icons.arrow_back, () {
              _nudge(-160, 0);
            }),
            const SizedBox(width: _gap),
            _controlButton(Icons.my_location, () {
              _center();
            }, filled: true),
            const SizedBox(width: _gap),
            _controlButton(Icons.arrow_forward, () {
              _nudge(160, 0);
            }),
          ],
        ),
        const SizedBox(height: _gap),
        _controlButton(Icons.arrow_downward, () {
          _nudge(0, 160);
        }),
        const SizedBox(height: _gap),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _controlButton(Icons.remove, () {
              _stepZoom(-1);
            }),
            const SizedBox(width: _control),
            _controlButton(Icons.add, () {
              _stepZoom(1);
            }),
          ],
        ),
      ],
    );
  }

  Widget _controlButton(
    IconData icon,
    VoidCallback onTap, {
    bool filled = false,
  }) {
    return BigIcon(icon: icon, extent: _control, filled: filled, onTap: onTap);
  }
}
