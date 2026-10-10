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
import 'mine_screen.dart';
import 'post_screen.dart';
import 'session.dart';

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
    });
  }

  Future<void> _load() async {
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
      });
    }
    try {
      final fresh = await session.api.feed(
        parentId: parent,
        lat: session.lat!,
        lng: session.lng!,
        lang: session.lang ?? 'en',
      );
      if (!mounted) return;
      if (fresh == null) {
        setState(() => _loading = false);
        return;
      }
      session.feedCache[key] = fresh;
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
    setState(() {
      _parents.add(id);
      _openId = null;
      _loading = true;
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
                            setState(() {
                              _parents.removeLast();
                              _openId = null;
                              _loading = true;
                            });
                            _load();
                          } else {
                            Navigator.pop(context);
                          }
                        },
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
                    setState(() => _loading = true);
                    _load();
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
                        onOpen: (id) => setState(() => _openId = id),
                        onClose: () => setState(() => _openId = null),
                        open: _openPost(posts),
                        categoryName: _nameFor(_openPost(posts)),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
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

  FeedPost? _openPost(List<FeedPost> posts) {
    for (final post in posts) {
      if (post.id == _openId) return post;
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

const _tileColors = <Color>[
  Color(0xFF0F6E56),
  Color(0xFF1A73E8),
  Color(0xFFB45309),
  Color(0xFF7C3AED),
  Color(0xFF0F766E),
  Color(0xFFBE185D),
  Color(0xFF0369A1),
  Color(0xFF3F6212),
];

Color _tileColor(String id) {
  var hash = 0;
  for (final unit in id.codeUnits) {
    hash = (hash + unit) & 0x7fffffff;
  }
  return _tileColors[hash % _tileColors.length];
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
    return Column(
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
                      decoration: BoxDecoration(
                        color: _tileColor(row.id),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        job ? Icons.badge : Icons.folder,
                        color: Colors.white,
                        size: 36,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        row.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 20),
                      ),
                    ),
                    if (!job)
                      const Icon(Icons.chevron_right, size: 28)
                    else if (picking)
                      const Icon(Icons.arrow_forward, size: 28),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (job)
          SizedBox(
            height: openId != null && row.posts.any((post) => post.id == openId)
                ? 540
                : 210,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(12),
              itemCount: row.posts.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final post = row.posts[index];
                final open = post.id == openId;
                return GestureDetector(
                  onTap: () => onOpen(post.id),
                  child: open
                      ? Align(
                          alignment: Alignment.topCenter,
                          widthFactor: 1,
                          child: ExpandedCard(
                            post: post,
                            categoryName: row.name,
                          ),
                        )
                      : Align(
                          alignment: Alignment.topCenter,
                          widthFactor: 1,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Image.network(
                              post.posterUrl,
                              width: 150,
                              height: 190,
                              fit: BoxFit.cover,
                              cacheWidth: imageCacheWidth(context, 150),
                              errorBuilder: (_, _, _) => const SizedBox(
                                width: 150,
                                height: 190,
                                child: ColoredBox(color: Color(0xFFE7F2EE)),
                              ),
                            ),
                          ),
                        ),
                );
              },
            ),
          ),
      ],
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
  final AudioPlayer _audio = AudioPlayer();
  final PageController _pages = PageController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    unawaited(_ensureMedia().catchError((Object _) => <MediaItem>[]));
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
    if (controller == null || _playingUrl != url || !controller.value.isInitialized) {
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
    return SizedBox(
      width: wide ? double.infinity : 280,
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
            BigIcon(icon: Icons.graphic_eq, onTap: () => _playAudio(item.url)),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: wide ? 16 : 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if ((widget.categoryName ?? '').isNotEmpty)
                  Text(
                    widget.categoryName!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.calendar_today, size: 22),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        _when(context),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      widget.post.band == 'near'
                          ? Icons.place
                          : widget.post.band == 'mid'
                          ? Icons.directions_walk
                          : Icons.public,
                      size: 22,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      widget.post.km == null
                          ? _bandLabel(l10n)
                          : '${widget.post.km} km',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    for (final code in widget.post.langs)
                      LangTile(
                        code: code,
                        compact: true,
                        extent: 56,
                        selected: false,
                        onTap: () => Speaker.clip(code),
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (!widget.mine)
            Row(
              mainAxisAlignment: wide
                  ? MainAxisAlignment.spaceEvenly
                  : MainAxisAlignment.start,
              children: [
                BigIcon(
                  icon: Icons.chat,
                  label: 'WhatsApp',
                  filled: true,
                  color: const Color(0xFF25D366),
                  onTap: () => _open('whatsapp'),
                ),
                BigIcon(
                  icon: Icons.call,
                  filled: true,
                  color: const Color(0xFF1A73E8),
                  onTap: () => _open('phone'),
                ),
                BigIcon(
                  icon: Icons.mail,
                  filled: true,
                  color: const Color(0xFFC5221F),
                  onTap: () => _open('gmail'),
                ),
              ],
            ),
        ],
      ),
    );
  }

  String _when(BuildContext context) {
    final ms = widget.post.createdAt;
    if (ms == null) return '${widget.post.daysAgo}';
    final locale = Localizations.localeOf(context).toString();
    return DateFormat.yMMMd(locale).format(
      DateTime.fromMillisecondsSinceEpoch(ms),
    );
  }

  String _bandLabel(AppLocalizations l10n) {
    if (widget.post.band == 'near') return l10n.near;
    if (widget.post.band == 'mid') return l10n.mid;
    return l10n.far;
  }

  Widget _poster(int cacheWidth) {
    final poster = widget.post.posterUrl;
    if (poster.isEmpty) return const ColoredBox(color: Color(0xFFE7F2EE));
    return Image.network(
      poster,
      key: ValueKey(poster),
      fit: BoxFit.cover,
      gaplessPlayback: true,
      cacheWidth: imageCacheWidth(context, cacheWidth.toDouble()),
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

  Future<void> _open(String channel) async {
    final session = SessionHost.of(context);
    final retry = AppLocalizations.of(context).tryAgain;
    try {
      final url = await session.api.reveal(widget.post.id, channel);
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      await Speaker.say(session.lang, retry);
    }
  }
}

class _MapPane extends StatefulWidget {
  const _MapPane({
    required this.posts,
    required this.lat,
    required this.lng,
    required this.onOpen,
    required this.onClose,
    required this.open,
    required this.categoryName,
  });

  final List<FeedPost> posts;
  final double lat;
  final double lng;
  final ValueChanged<String> onOpen;
  final VoidCallback onClose;
  final FeedPost? open;
  final String? categoryName;

  @override
  State<_MapPane> createState() => _MapPaneState();
}

class _MapPaneState extends State<_MapPane> {
  MapLibreMapController? _controller;

  static const _zoom = 17.0;

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
          CameraUpdate.newLatLngZoom(points.first, _zoom),
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
          left: 48,
          top: 48,
          right: 48,
          bottom: 48,
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
    if (best != null) widget.onOpen(best.id);
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
      for (final post in widget.posts) {
        await controller.addCircle(
          CircleOptions(
            geometry: LatLng(post.lat, post.lng),
            circleColor: '#0F6E56',
            circleRadius: 18,
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
    if (moved || postsChanged) _center();
    if (postsChanged) _draw();
    if (oldWidget.open?.id != widget.open?.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _controller?.forceResizeWebMap();
      });
    }
  }

  bool _samePosts(List<FeedPost> a, List<FeedPost> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final open = widget.open;
    return Column(
      children: [
        Expanded(flex: open == null ? 1 : 2, child: _map()),
        if (open != null)
          Expanded(
            flex: 3,
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
                    child: SingleChildScrollView(
                      child: ExpandedCard(
                        post: open,
                        wide: true,
                        categoryName: widget.categoryName,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _map() {
    return MapLibreMap(
      styleString: 'https://tiles.openfreemap.org/styles/liberty',
      initialCameraPosition: CameraPosition(
        target: LatLng(widget.lat, widget.lng),
        zoom: _zoom,
      ),
      onMapCreated: (controller) {
        _controller = controller;
        controller.onCircleTapped.add((circle) {
          final id = circle.data?['postId'];
          if (id is String) widget.onOpen(id);
        });
      },
      featureTapsTriggersMapClick: true,
      onMapClick: (_, latLng) => _openNearest(latLng),
      onStyleLoadedCallback: _onStyle,
      myLocationEnabled: false,
    );
  }
}
