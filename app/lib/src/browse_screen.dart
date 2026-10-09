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
                          MaterialPageRoute<void>(builder: (_) => const MineScreen()),
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
                            onTap: (id) => setState(() => _openId = _openId == id ? null : id),
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
                                    onOpen: (id) => setState(() => _openId = _openId == id ? null : id),
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
            if (picking && job) BigIcon(icon: Icons.check_circle, onTap: onPick),
          ],
        ),
        if (job)
        SizedBox(
          height: openId != null && row.posts.any((post) => post.id == openId) ? 460 : 210,
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
                    ? ExpandedCard(post: post)
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.network(
                          post.posterUrl,
                          width: 150,
                          height: 190,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const SizedBox(
                            width: 150,
                            height: 190,
                            child: ColoredBox(color: Color(0xFFE7F2EE)),
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
  const ExpandedCard({required this.post, this.mine = false, super.key});

  final FeedPost post;
  final bool mine;

  @override
  State<ExpandedCard> createState() => _ExpandedCardState();
}

class _ExpandedCardState extends State<ExpandedCard> {
  List<MediaItem> _media = [];
  VideoPlayerController? _video;

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
    _video?.dispose();
    super.dispose();
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
    final frames = _media.where((item) => item.kind == 'image' || item.kind == 'video').toList();
    final shown = frames.isEmpty
        ? [MediaItem(id: '', kind: 'image', url: widget.post.posterUrl)]
        : frames;
    return SizedBox(
      width: 280,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 320,
            child: PageView(
              children: [
                for (final item in shown)
                  Stack(
                    fit: StackFit.expand,
                    children: [
                      if (item.kind == 'video' && _video != null && _video!.dataSource == item.url)
                        VideoPlayer(_video!)
                      else
                        Image.network(item.url, fit: BoxFit.cover),
                      if (item.kind == 'video')
                        Center(
                          child: BigIcon(
                            icon: Icons.play_arrow,
                            filled: true,
                            onTap: () => _play(item.url),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
          Row(
            children: [
              Text('${widget.post.daysAgo}', style: const TextStyle(fontSize: 16)),
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
          if (!widget.mine)
            Row(
              children: [
                BigIcon(
                  icon: Icons.chat,
                  label: 'WhatsApp',
                  onTap: () => _open('whatsapp'),
                ),
                BigIcon(icon: Icons.call, onTap: () => _open('phone')),
                BigIcon(icon: Icons.mail, onTap: () => _open('gmail')),
              ],
            ),
        ],
      ),
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
    required this.onTap,
    required this.open,
  });

  final List<FeedPost> posts;
  final double lat;
  final double lng;
  final ValueChanged<String> onTap;
  final FeedPost? open;

  @override
  State<_MapPane> createState() => _MapPaneState();
}

class _MapPaneState extends State<_MapPane> {
  MapLibreMapController? _controller;

  Future<void> _center() async {
    final controller = _controller;
    if (controller == null) return;
    try {
      await controller.moveCamera(
        CameraUpdate.newLatLngZoom(LatLng(widget.lat, widget.lng), 15),
      );
    } catch (_) {}
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
          {'id': post.id},
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
    return Column(
      children: [
        Expanded(
          child: MapLibreMap(
            styleString: 'https://tiles.openfreemap.org/styles/liberty',
            initialCameraPosition: CameraPosition(target: LatLng(widget.lat, widget.lng), zoom: 15),
            onMapCreated: (controller) {
              _controller = controller;
              controller.onCircleTapped.add((circle) {
                final id = circle.data?['id'];
                if (id is String) widget.onTap(id);
              });
            },
            onStyleLoadedCallback: _onStyle,
            myLocationEnabled: false,
          ),
        ),
        if (widget.open != null)
          SizedBox(
            height: 460,
            child: SingleChildScrollView(
              child: Center(child: ExpandedCard(post: widget.open!)),
            ),
          ),
      ],
    );
  }
}
