import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/material.dart';
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
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final session = SessionHost.of(context);
      final l10n = AppLocalizations.of(context);
      await Speaker.say(session.lang, l10n.near);
      await _load();
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
            : FloatingActionButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const PostScreen()),
                  );
                },
                child: const Icon(Icons.add_a_photo),
              ),
        body: SafeArea(
          child: Column(
            children: [
              Row(
                children: [
                  if (_parents.length > 1 || widget.picking)
                    BigIcon(
                      icon: Icons.arrow_back,
                      label: l10n.back,
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
                      onTap: () => setState(() => _map = !_map),
                    ),
                  if (!widget.picking)
                    BigIcon(
                      icon: Icons.person,
                      label: l10n.mine,
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
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView(
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
            InkWell(
              onTap: () {
                Speaker.say(SessionHost.of(context).lang, row.name);
                if (!job) onDrill();
              },
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.network(
                      row.coverUrl,
                      width: 72,
                      height: 72,
                      fit: BoxFit.cover,
                      cacheWidth: imageCacheWidth(context, 72),
                      errorBuilder: (_, _, _) => const SizedBox(
                        width: 72,
                        height: 72,
                        child: ColoredBox(color: Color(0xFFE7F2EE)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(row.name, style: const TextStyle(fontSize: 14)),
                ],
              ),
            ),
            if (picking && job)
              BigIcon(icon: Icons.check_circle, onTap: onPick),
          ],
        ),
        if (job)
          SizedBox(
            height: openId != null && row.posts.any((post) => post.id == openId)
                ? 460
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
                          child: ExpandedCard(post: post),
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
    this.mine = false,
    this.wide = false,
    super.key,
  });

  final FeedPost post;
  final bool mine;
  final bool wide;

  @override
  State<ExpandedCard> createState() => _ExpandedCardState();
}

class _ExpandedCardState extends State<ExpandedCard> {
  List<MediaItem> _media = [];
  VideoPlayerController? _video;
  final AudioPlayer _audio = AudioPlayer();
  final PageController _pages = PageController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final detail = await SessionHost.of(context).api.post(widget.post.id);
      if (!mounted) return;
      setState(() => _media = detail.media);
    } catch (_) {}
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
    await _video?.dispose();
    final controller = VideoPlayerController.networkUrl(Uri.parse(url));
    await controller.initialize();
    await controller.play();
    if (!mounted) return;
    setState(() => _video = controller);
  }

  @override
  Widget build(BuildContext context) {
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
                        if (videos.isNotEmpty)
                          Center(
                            child: BigIcon(
                              icon: Icons.play_arrow,
                              filled: true,
                              onTap: () {
                                _pages.animateToPage(
                                  1,
                                  duration: const Duration(milliseconds: 250),
                                  curve: Curves.easeOut,
                                );
                                _play(videos.first.url);
                              },
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
            BigIcon(icon: Icons.play_arrow, onTap: () => _playAudio(item.url)),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: wide ? 16 : 0),
            child: Row(
              children: [
                Text(
                  '${widget.post.daysAgo}',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  widget.post.band == 'near'
                      ? Icons.place
                      : widget.post.band == 'mid'
                      ? Icons.directions_walk
                      : Icons.public,
                  size: 22,
                ),
                const SizedBox(width: 8),
                for (final code in widget.post.langs)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: LangTile(
                      code: code,
                      compact: true,
                      selected: false,
                      onTap: () => Speaker.clip(code),
                    ),
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
                  filled: wide,
                  onTap: () => _open('whatsapp'),
                ),
                BigIcon(
                  icon: Icons.call,
                  filled: wide,
                  onTap: () => _open('phone'),
                ),
                BigIcon(
                  icon: Icons.mail,
                  filled: wide,
                  onTap: () => _open('gmail'),
                ),
              ],
            ),
        ],
      ),
    );
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

  Widget _videoPage(MediaItem item) {
    final playing = _video != null && _video!.dataSource == item.url;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (playing) VideoPlayer(_video!) else _poster(widget.wide ? 360 : 280),
        Center(
          child: BigIcon(
            icon: Icons.play_arrow,
            filled: true,
            onTap: () => _play(item.url),
          ),
        ),
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
  });

  final List<FeedPost> posts;
  final double lat;
  final double lng;
  final ValueChanged<String> onOpen;
  final VoidCallback onClose;
  final FeedPost? open;

  @override
  State<_MapPane> createState() => _MapPaneState();
}

class _MapPaneState extends State<_MapPane> {
  MapLibreMapController? _controller;

  static const _zoom = 17.0;

  Future<void> _center() async {
    final controller = _controller;
    if (controller == null) return;
    try {
      await controller.animateCamera(
        CameraUpdate.newLatLngZoom(LatLng(widget.lat, widget.lng), _zoom),
        duration: const Duration(milliseconds: 350),
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
    if (oldWidget.lat != widget.lat || oldWidget.lng != widget.lng) {
      _center();
    }
    if (!_samePosts(oldWidget.posts, widget.posts)) _draw();
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
                      child: ExpandedCard(post: open, wide: true),
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
