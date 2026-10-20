import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:circle_flags/circle_flags.dart';
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
  Session? _session;
  double? _seenLat;
  double? _seenLng;
  var _pulling = false;

  @override
  void initState() {
    super.initState();
    FirebaseAnalytics.instance.logScreenView(screenName: 'browse');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final session = SessionHost.of(context);
      _session = session;
      session.addListener(_onSession);
      final l10n = AppLocalizations.of(context);
      unawaited(Speaker.say(session.lang, l10n.near));
      unawaited(_load());
    });
  }

  @override
  void dispose() {
    _session?.removeListener(_onSession);
    super.dispose();
  }

  void _onSession() {
    final session = _session;
    if (_pulling || !mounted || session == null) return;
    final lat = session.lat;
    final lng = session.lng;
    if (lat == null || lng == null) return;
    if (_seenLat == null) {
      _seenLat = lat;
      _seenLng = lng;
      return;
    }
    if (lat == _seenLat && lng == _seenLng) {
      if (session.feedBypass) unawaited(_load());
      return;
    }
    _seenLat = lat;
    _seenLng = lng;
    final key = session.cacheKey(_parents.last);
    if (!session.feedIsFresh(key, lat, lng)) {
      unawaited(_load());
      return;
    }
    setState(() => _rows = session.visible(key, lat, lng));
  }

  void _paintCached(Session session) {
    final key = session.cacheKey(_parents.last);
    if (session.feedCache.containsKey(key) && session.lat != null) {
      _rows = session.visible(key, session.lat!, session.lng!);
      _loading = false;
    } else {
      _loading = true;
    }
  }

  Future<void> _load({bool force = false}) async {
    final session = SessionHost.of(context);
    _pulling = true;
    try {
      await _loadAt(session, force: force);
    } finally {
      _pulling = false;
    }
  }

  Future<void> _loadAt(Session session, {required bool force}) async {
    final ok = await session.locate();
    if (!ok || session.lat == null || session.lng == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
      return;
    }
    final parent = _parents.last;
    final key = session.cacheKey(parent);
    final lat = session.lat!;
    final lng = session.lng!;
    _seenLat = lat;
    _seenLng = lng;
    if (!widget.picking && session.feedCache.containsKey(key) && mounted) {
      setState(() {
        _rows = session.visible(key, lat, lng);
        _loading = false;
        _failed = false;
      });
      if (!force && session.feedIsFresh(key, lat, lng)) return;
    }
    final bypass = session.feedBypass;
    session.feedBypass = false;
    final live = force || bypass;
    final lang = session.lang ?? 'en';
    try {
      var page = await session.api.feed(
        parentId: parent,
        lat: lat,
        lng: lng,
        lang: lang,
        headersOnly: widget.picking,
        fresh: live,
        conditional: session.feedCache.containsKey(key),
      );
      if (!mounted) return;
      if (page == null && !session.feedCache.containsKey(key)) {
        session.api.forgetFeed(
          parentId: parent,
          lat: lat,
          lng: lng,
          lang: lang,
          headersOnly: widget.picking,
          fresh: live,
        );
        page = await session.api.feed(
          parentId: parent,
          lat: lat,
          lng: lng,
          lang: lang,
          headersOnly: widget.picking,
          fresh: live,
        );
        if (!mounted) return;
      }
      if (page == null) {
        if (session.feedCache.containsKey(key)) {
          setState(() {
            _rows = session.visible(key, lat, lng);
            _loading = false;
          });
          return;
        }
        setState(() {
          _loading = false;
          _failed = true;
        });
        await Speaker.say(session.lang, AppLocalizations.of(context).tryAgain);
        return;
      }
      if (!widget.picking) {
        session.rememberFeed(key, page, lat: lat, lng: lng);
      }
      final rows = widget.picking
          ? [
              for (final row in page.categories)
                row.copyWith(posts: const []),
            ]
          : session.visible(key, lat, lng);
      setState(() {
        _rows = rows;
        _loading = false;
        _failed = false;
      });
    } catch (_) {
      if (bypass) session.feedBypass = true;
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
                    if (session.lat != null && session.country != null)
                      Semantics(
                        label: session.countryName ?? session.country!,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.black12),
                          ),
                          child: CircleFlag(session.country!, size: 16),
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
  'oil-refineries': Icons.factory,
  'staff-nurse': Icons.health_and_safety,
  'anm': Icons.child_care,
  'ward-boy': Icons.accessible,
  'ayah': Icons.volunteer_activism,
  'housekeeping': Icons.sanitizer,
  'lab-technician': Icons.biotech,
  'pharmacist': Icons.medication,
  'plant-helper': Icons.engineering,
  'fitter': Icons.build,
  'welder': Icons.whatshot,
  'rigger': Icons.precision_manufacturing,
  'scaffolder': Icons.view_week,
  'electrician': Icons.electrical_services,
  'process-operator': Icons.tune,
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

  void _activate(BuildContext context) {
    Speaker.say(SessionHost.of(context).lang, row.name);
    if (!row.isJob) {
      onDrill();
    } else if (picking) {
      onPick();
    }
  }

  Widget _name() {
    return Text(
      row.name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontSize: 20,
        color: Color(0xFF14281D),
        fontWeight: FontWeight.w700,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!row.isJob) return _folder(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => _activate(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(child: _name()),
                  if (picking)
                    const Icon(
                      Icons.arrow_forward,
                      size: 28,
                      color: Color(0xFF14281D),
                    ),
                ],
              ),
            ),
          ),
          if (!picking)
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

  Widget _folder(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Color(0xFFF5F3F0),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE4E2DF)),
        ),
        child: SizedBox(
          height: 96,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                SizedBox(
                  width: 84,
                  height: 68,
                  child: Stack(
                    children: [
                      const Positioned(
                        left: 28,
                        top: 0,
                        child: _Peek(color: Color(0xFFE4E2DF)),
                      ),
                      const Positioned(
                        left: 14,
                        top: 6,
                        child: _Peek(color: Color(0xFFD9E6DC)),
                      ),
                      Positioned(
                        left: 0,
                        top: 12,
                        child: BigIcon(
                          icon: _rowIcon(row),
                          extent: 56,
                          onTap: () => _activate(context),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: InkWell(
                    onTap: () => _activate(context),
                    child: SizedBox(
                      height: 96,
                      child: Row(
                        children: [
                          Expanded(child: _name()),
                          const Icon(
                            Icons.chevron_right,
                            size: 28,
                            color: Color(0xFF14281D),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Peek extends StatelessWidget {
  const _Peek({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const SizedBox(width: 44, height: 48),
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
                    borderRadius: BorderRadius.circular(20),
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
                        child: ColoredBox(color: Color(0xFFD9E6DC)),
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
    this.categoryPath,
    this.mine = false,
    this.wide = false,
    this.tail,
    super.key,
  });

  final FeedPost post;
  final String? categoryName;
  final String? categoryPath;
  final bool mine;
  final bool wide;
  final Widget? tail;

  @override
  State<ExpandedCard> createState() => _ExpandedCardState();
}

class _ExpandedCardState extends State<ExpandedCard> {
  List<MediaItem> _media = [];
  VideoPlayerController? _video;
  String? _playingUrl;
  String? _preparingUrl;
  Future<void>? _prepareTask;
  bool _showPause = false;
  int _playToken = 0;
  bool _ready = false;
  Future<List<MediaItem>>? _detail;
  String? _reachNote;
  bool? _detailMine;
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
        _detailMine = detail.mine;
      });
      _kickPrepare(detail.media);
      return detail.media;
    } catch (_) {
      _detail = null;
      if (mounted) setState(() => _detailMine = false);
      rethrow;
    }
  }

  @override
  void dispose() {
    _preparingUrl = null;
    _pages.dispose();
    _video?.dispose();
    unawaited(_audio.dispose());
    super.dispose();
  }

  Future<void> _playAudio(String url) async {
    await _audio.stop();
    await _audio.play(UrlSource(url));
  }

  void _kickPrepare(List<MediaItem> media) {
    for (final item in media) {
      if (item.kind != 'video' || item.url.isEmpty) continue;
      if (_preparingUrl == item.url || _playingUrl == item.url) return;
      _preparingUrl = item.url;
      _prepareTask = _prepare(item.url);
      return;
    }
  }

  Future<void> _prepare(String url) async {
    final controller = VideoPlayerController.networkUrl(Uri.parse(url));
    try {
      await controller.initialize();
      await controller.setLooping(false);
      _watch(controller);
    } catch (_) {
      await controller.dispose();
      if (mounted && _preparingUrl == url) {
        _preparingUrl = null;
        _prepareTask = null;
      }
      return;
    }
    if (!mounted || _preparingUrl != url) {
      await controller.dispose();
      return;
    }
    setState(() {
      _video = controller;
      _playingUrl = url;
    });
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
    if (_preparingUrl == url && _video == null) await _prepareTask;
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
    final audios = _media.where((item) => item.kind == 'audio').toList();
    final wide = widget.wide;
    final cacheWidth = wide ? 360 : 280;
    final posterHeight = wide ? 220.0 : (audios.isEmpty ? 320.0 : 216.0);
    return Padding(
      padding: EdgeInsets.all(wide ? 12 : 0),
      child: Material(
        color: const Color(0xFFF5F3F0),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFFD9E6DC)),
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
                      height: posterHeight,
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
                              if (widget.post.country case final code?)
                                _flag(code),
                            ],
                          ),
                          for (final item in videos) _videoPage(item),
                        ],
                      ),
                    ),
                  ),
                ),
                if (audios.isNotEmpty) _audioRow(audios, l10n),
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
                            color: Color(0xFF14281D),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0xFFD9E6DC),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if ((widget.categoryPath ?? '').isNotEmpty) ...[
                                _fact(
                                  Icons.category,
                                  widget.categoryPath!,
                                  maxLines: 2,
                                ),
                                const SizedBox(height: 4),
                              ],
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
                if (widget.tail case final tail?)
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      wide ? 16 : 0,
                      8,
                      wide ? 16 : 0,
                      0,
                    ),
                    child: tail,
                  ),
                if (!widget.mine) _contactActions(l10n),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _audioRow(List<MediaItem> audios, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          for (var i = 0; i < audios.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: BigIcon(
                icon: Icons.graphic_eq,
                label: audios.length == 1
                    ? l10n.addAudio
                    : '${l10n.addAudio} ${i + 1}',
                compact: true,
                stretch: true,
                onTap: () => _playAudio(audios[i].url),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _contactActions(AppLocalizations l10n) {
    final own = _detailMine == true;
    final row = Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Expanded(
            child: BigIcon(
              icon: Icons.chat,
              label: 'WhatsApp',
              filled: true,
              compact: true,
              stretch: true,
              color: const Color(0xFF25D366),
              onTap: own ? null : () => _open('whatsapp'),
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
              onTap: own ? null : () => _open('phone'),
            ),
          ),
        ],
      ),
    );
    if (!own) return row;
    return ExcludeSemantics(
      child: Opacity(
        opacity: 0.45,
        child: GestureDetector(
          onTap: () {},
          behavior: HitTestBehavior.opaque,
          child: row,
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
        Icon(icon, size: 22, color: const Color(0xFF3A684D)),
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
              color: Color(0xFF14281D),
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
    final thumb = widget.post.thumbUrl;
    if (poster.isEmpty && thumb.isEmpty) {
      return const ColoredBox(color: Color(0xFFD9E6DC));
    }
    final showPoster = poster.isNotEmpty && poster != thumb;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (thumb.isNotEmpty)
          NetImage(
            url: thumb,
            fit: BoxFit.cover,
            cacheLogical: cacheWidth.toDouble(),
          ),
        if (showPoster || thumb.isEmpty)
          NetImage(
            url: poster,
            fit: BoxFit.cover,
            cacheLogical: cacheWidth.toDouble(),
          ),
      ],
    );
  }

  Widget _flag(String code) {
    return Positioned(
      top: 8,
      right: 8,
      child: Semantics(
        label: code,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 1.5),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 4,
                offset: Offset(0, 1),
              ),
            ],
          ),
          child: CircleFlag(code, size: 18),
        ),
      ),
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
    final l10n = AppLocalizations.of(context);
    final lines = <String>[l10n.reachNote, ''];
    final title = (widget.categoryName ?? '').trim();
    if (title.isNotEmpty) lines.add('*$title*');
    lines.add(l10n.reachPosted(_when(context)));
    final km = widget.post.km;
    lines.add(km == null ? _bandLabel(l10n) : l10n.reachAway(km));
    if (widget.post.langs.isNotEmpty) {
      lines.add(
        '${l10n.speaks} ${widget.post.langs.map((code) => kAutonym[code] ?? code).join(' · ')}',
      );
    }
    final lat = session.lat;
    final lng = session.lng;
    if (lat != null && lng != null) {
      lines
        ..add('')
        ..add('${l10n.useMyPlace}:')
        ..add(
          'https://maps.google.com/?q=${lat.toStringAsFixed(5)},${lng.toStringAsFixed(5)}',
        );
    }
    lines
      ..add('')
      ..add(l10n.reachAsk);
    return lines.join('\n');
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
    } on ApiException catch (error) {
      if (!mounted) return;
      final line = error.dayCap
          ? AppLocalizations.of(context).opensUsed
          : retry;
      await Speaker.say(session.lang, line);
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
    if (!validPhone('+$digits')) return false;
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
  var _fitAttempted = false;

  static const _userZoom = 17.0;
  static const _fitCap = 15.0;
  static const _control = 40.0;
  static const _gap = 4.0;
  static const _padClear = 12.0;
  static const _sideClear = _control * 3 + _gap * 2 + 16;

  List<LatLng> _pinPoints() => [
    for (final post in widget.posts) LatLng(post.lat, post.lng),
  ];

  Future<void> _fitPins({bool allowRetry = true}) async {
    final controller = _controller;
    if (controller == null) return;
    final points = _pinPoints();
    if (points.isEmpty) {
      await _zoomToUser();
      return;
    }
    if (!await _hasSize(controller)) {
      try {
        await _spanZoom(controller, points);
      } catch (_) {}
      if (allowRetry) _scheduleFit();
      return;
    }
    final zoom = _zoomFor(points);
    try {
      if (zoom >= _fitCap) {
        await _move(controller, _abovePad(_middle(points), _fitCap), _fitCap);
        return;
      }
      await controller.animateCamera(
        CameraUpdate.newLatLngBounds(
          _bounds(points),
          left: 24,
          top: 24,
          right: _sideClear,
          bottom: _padClear,
        ),
        duration: const Duration(milliseconds: 350),
      );
    } catch (_) {
      try {
        await _spanZoom(controller, points);
      } catch (_) {
        if (allowRetry) _scheduleFit();
      }
    }
  }

  void _scheduleFit() {
    if (_fitAttempted) return;
    _fitAttempted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _fitPins(allowRetry: false);
    });
  }

  Future<bool> _hasSize(MapLibreMapController controller) async {
    try {
      final region = await controller.getVisibleRegion();
      final latSpan = (region.northeast.latitude - region.southwest.latitude)
          .abs();
      final lngSpan = (region.northeast.longitude - region.southwest.longitude)
          .abs();
      return latSpan > 1e-6 && lngSpan > 1e-6;
    } catch (_) {
      return false;
    }
  }

  Future<void> _spanZoom(
    MapLibreMapController controller,
    List<LatLng> points,
  ) {
    return _move(controller, _middle(points), _zoomFor(points));
  }

  Future<void> _move(
    MapLibreMapController controller,
    LatLng target,
    double zoom,
  ) {
    return controller
        .animateCamera(
          CameraUpdate.newLatLngZoom(target, zoom),
          duration: const Duration(milliseconds: 350),
        )
        .then((_) {});
  }

  Future<void> _zoomToUser() async {
    final controller = _controller;
    if (controller == null) return;
    try {
      await _move(
        controller,
        _abovePad(LatLng(widget.lat, widget.lng), _userZoom),
        _userZoom,
      );
    } catch (_) {}
  }

  Future<void> _focusPin(String id) async {
    final controller = _controller;
    if (controller == null) return;
    FeedPost? post;
    for (final item in widget.posts) {
      if (item.id == id) post = item;
    }
    if (post == null) return;
    try {
      await _move(
        controller,
        _abovePad(LatLng(post.lat, post.lng), _fitCap),
        _fitCap,
      );
    } catch (_) {}
  }

  LatLngBounds _bounds(List<LatLng> points) {
    var minLat = points.first.latitude;
    var maxLat = minLat;
    var minLng = points.first.longitude;
    var maxLng = minLng;
    for (final point in points.skip(1)) {
      minLat = math.min(minLat, point.latitude);
      maxLat = math.max(maxLat, point.latitude);
      minLng = math.min(minLng, point.longitude);
      maxLng = math.max(maxLng, point.longitude);
    }
    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }

  LatLng _middle(List<LatLng> points) {
    final box = _bounds(points);
    return LatLng(
      (box.southwest.latitude + box.northeast.latitude) / 2,
      (box.southwest.longitude + box.northeast.longitude) / 2,
    );
  }

  double _zoomFor(List<LatLng> points) {
    final box = _bounds(points);
    const width = 240.0;
    const height = 280.0;
    const tile = 256.0;
    final lngFrac = math.max(
      (box.northeast.longitude - box.southwest.longitude).abs() / 360,
      1e-6,
    );
    final latFrac = math.max(
      (_mercator(box.southwest.latitude) - _mercator(box.northeast.latitude))
          .abs(),
      1e-6,
    );
    final zoomLng = math.log(width / tile / lngFrac) / math.ln2;
    final zoomLat = math.log(height / tile / latFrac) / math.ln2;
    return math.min(zoomLng, zoomLat).clamp(1.0, _fitCap);
  }

  double _mercator(double lat) {
    final clamped = lat.clamp(-85.0, 85.0);
    final s = math.sin(clamped * math.pi / 180);
    return 0.5 - math.log((1 + s) / (1 - s)) / (4 * math.pi);
  }

  double _openZoom() {
    final points = _pinPoints();
    if (points.isEmpty) return _userZoom;
    return _zoomFor(points);
  }

  LatLng _openTarget() {
    final points = _pinPoints();
    if (points.isEmpty) {
      return _abovePad(LatLng(widget.lat, widget.lng), _userZoom);
    }
    final zoom = _zoomFor(points);
    final middle = _middle(points);
    if (zoom >= _fitCap) return _abovePad(middle, _fitCap);
    return middle;
  }

  LatLng _abovePad(LatLng point, double zoom) {
    final metersPerPixel =
        156543.03392 *
        math.cos(point.latitude * math.pi / 180) /
        math.pow(2, zoom);
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
    final zoom = _controller?.cameraPosition?.zoom ?? _userZoom;
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
    await _fitPins();
    await _draw();
  }

  @override
  void didUpdateWidget(covariant _MapPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    final moved = oldWidget.lat != widget.lat || oldWidget.lng != widget.lng;
    final postsChanged = !_samePosts(oldWidget.posts, widget.posts);
    if (postsChanged) {
      _fitAttempted = false;
      _fitPins();
    } else if (moved && widget.posts.isEmpty) {
      _zoomToUser();
    }
    if (moved || postsChanged) _draw();
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
        final cell = pin == null ? widget.posts : _cellPosts(pin);
        final expanded =
            widget.openId != null &&
            cell.any((post) => post.id == widget.openId);
        final cap = math.max(0.0, constraints.maxHeight - _padClear);
        final wanted = 48.0 + (expanded ? 560.0 : 210.0);
        final sheetHeight = math.min(wanted, cap);
        final showSheet = cell.isNotEmpty && sheetHeight >= 48;
        return Column(
          children: [
            Expanded(child: _map()),
            if (showSheet)
              SizedBox(
                height: sheetHeight,
                child: Material(
                  color: const Color(0xFFF5F3F0),
                  elevation: 0,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
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
                                color: const Color(0xFFE4E2DF),
                                borderRadius: BorderRadius.circular(99),
                              ),
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: IconButton(
                                onPressed: widget.onClose,
                                icon: const Icon(Icons.close),
                                style: IconButton.styleFrom(
                                  backgroundColor: const Color(0xFFF5F3F0),
                                  foregroundColor: const Color(0xFF14281D),
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
                          onOpen: (id) {
                            _focusPin(id);
                            widget.onOpen(id);
                          },
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
            target: _openTarget(),
            zoom: _openZoom(),
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
              _zoomToUser();
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
