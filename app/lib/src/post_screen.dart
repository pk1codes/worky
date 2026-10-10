import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:record/record.dart';

import '../l10n/app_localizations.dart';
import 'api.dart';
import 'browse_screen.dart';
import 'chrome.dart';
import 'langs.dart';
import 'local_thumb.dart' if (dart.library.io) 'local_thumb_io.dart';
import 'media_queue.dart';
import 'session.dart';

class PostScreen extends StatefulWidget {
  const PostScreen({this.edit, super.key});

  final FeedPost? edit;

  @override
  State<PostScreen> createState() => _PostScreenState();
}

class _PostScreenState extends State<PostScreen> {
  var _step = 0;
  String? _categoryId;
  double? _lat;
  double? _lng;
  late Set<String> _langs;
  final List<String> _mediaIds = [];
  final List<String> _jobIds = [];
  final ImagePicker _picker = ImagePicker();
  final AudioRecorder _recorder = AudioRecorder();
  var _recording = false;
  String? _micId;
  MediaQueue? _box;
  List<MediaItem> _library = [];
  MapLibreMapController? _map;

  @override
  void initState() {
    super.initState();
    FirebaseAnalytics.instance.logScreenView(screenName: 'post');
    _langs = {
      widget.edit?.langs.isNotEmpty == true ? widget.edit!.langs.first : 'hi',
    };
    _lat = widget.edit?.lat;
    _lng = widget.edit?.lng;
    _categoryId = widget.edit?.categoryId;
    _mediaIds.addAll(widget.edit?.mediaIds ?? const []);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final session = SessionHost.of(context);
      _langs = {
        if (widget.edit != null)
          ...widget.edit!.langs
        else
          session.lang ?? 'hi',
      };
      _lat ??= session.lat;
      _lng ??= session.lng;
      if (mounted) setState(() {});
      unawaited(Speaker.say(session.lang, AppLocalizations.of(context).post));
      try {
        final library = await session.api.library();
        if (mounted) setState(() => _library = library);
      } catch (_) {}
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final box = SessionHost.of(context).outbox;
    if (_box == box) return;
    _box?.removeListener(_onBox);
    _box = box;
    box.addListener(_onBox);
  }

  void _onBox() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _box?.removeListener(_onBox);
    unawaited(_recorder.dispose());
    super.dispose();
  }

  void _take(Session session, String kind, String path, {String? contentType}) {
    final id = session.outbox.freshId();
    session.outbox.addFile(
      id: id,
      kind: kind,
      path: path,
      contentType: contentType,
    );
    setState(() => _jobIds.add(id));
  }

  Future<void> _pickImage(ImageSource source) async {
    final file = await _picker.pickImage(
      source: source,
      maxWidth: kIsWeb ? 1600 : null,
      maxHeight: kIsWeb ? 1600 : null,
      imageQuality: kIsWeb ? 80 : null,
    );
    if (file == null || !mounted) return;
    _take(
      SessionHost.of(context),
      'image',
      file.path,
      contentType: file.mimeType,
    );
  }

  Future<void> _pickVideo(ImageSource source) async {
    final file = await _picker.pickVideo(
      source: source,
      maxDuration: const Duration(seconds: 30),
    );
    if (file == null || !mounted) return;
    _take(SessionHost.of(context), 'video', file.path);
  }

  Future<void> _finishMic(Session session) async {
    if (!_recording) return;
    final path = await _recorder.stop();
    final id = _micId;
    _recording = false;
    _micId = null;
    if (path == null || id == null) return;
    session.outbox.addFile(id: id, kind: 'audio', path: path, ownsPath: true);
    _jobIds.add(id);
  }

  Future<void> _toggleMic() async {
    final session = SessionHost.of(context);
    if (_recording) {
      await _finishMic(session);
      if (mounted) setState(() {});
      return;
    }
    if (!await _recorder.hasPermission()) return;
    final id = session.outbox.freshId();
    final path = await session.outbox.localPath(id, 'm4a');
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 32000,
        sampleRate: 22050,
        numChannels: 1,
      ),
      path: path,
    );
    if (!mounted) return;
    setState(() {
      _recording = true;
      _micId = id;
    });
  }

  Future<void> _pickAudioFile() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3', 'm4a'],
    );
    if (files.isEmpty || !mounted) return;
    final path = files.first.path;
    if (path == null) return;
    _take(SessionHost.of(context), 'audio', path);
  }

  int _count(Session session, String kind) {
    var n = 0;
    for (final id in _mediaIds) {
      MediaItem? known;
      for (final item in _library) {
        if (item.id == id) known = item;
      }
      if (known == null) {
        if (_library.isEmpty && kind == 'image') n += 1;
      } else if (known.kind == kind) {
        n += 1;
      }
    }
    for (final id in _jobIds) {
      final item = session.outbox.job(id);
      if (item != null && item.kind == kind) n += 1;
    }
    return n;
  }

  Future<void> _save() async {
    final session = SessionHost.of(context);
    final message = AppLocalizations.of(context).tryAgain;
    await _finishMic(session);
    if (!mounted) return;
    final images = _count(session, 'image');
    final videos = _count(session, 'video');
    final audios = _count(session, 'audio');
    if (_categoryId == null ||
        _lat == null ||
        _lng == null ||
        images < 1 ||
        images > 5 ||
        videos > 5 ||
        audios > 5) {
      await Speaker.say(session.lang, message);
      return;
    }
    session.outbox.saveDraft(
      postId: widget.edit?.id,
      categoryId: _categoryId!,
      lat: _lat!,
      lng: _lng!,
      langs: _langs.toList(),
      libraryIds: List<String>.of(_mediaIds),
      jobIds: List<String>.of(_jobIds),
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final session = SessionHost.of(context);
    return Paged(
      page: 5,
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
                      onTap: () {
                        if (_step == 0) {
                          Navigator.pop(context);
                        } else {
                          setState(() => _step -= 1);
                        }
                      },
                    ),
                    const Spacer(),
                    for (var i = 0; i < 3; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(
                          Icons.circle,
                          size: 14,
                          color: i == _step
                              ? const Color(0xFF0F6E56)
                              : const Color(0xFFD5E5DF),
                        ),
                      ),
                    if (_step < 2)
                      BigIcon(
                        icon: Icons.arrow_forward,
                        label: l10n.continueAction,
                        compact: true,
                        onTap: _step == 0 && _categoryId == null
                            ? null
                            : () => setState(() => _step += 1),
                      )
                    else
                      BigIcon(
                        icon: Icons.check,
                        filled: true,
                        label: l10n.save,
                        compact: true,
                        onTap: _save,
                      ),
                  ],
                ),
              ),
              Text(
                _step == 0
                    ? l10n.admin
                    : _step == 1
                    ? l10n.location
                    : l10n.photos,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Expanded(
                child: _step == 0
                    ? _pickCategory()
                    : _step == 1
                    ? _place(session, l10n)
                    : _media(session, l10n),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pickCategory() {
    return BrowseScreen(
      picking: true,
      onPicked: (id) => setState(() {
        _categoryId = id;
        _step = 1;
      }),
    );
  }

  Future<void> _pin(double lat, double lng) async {
    final controller = _map;
    if (controller == null) return;
    try {
      await controller.clearCircles();
      await controller.addCircle(
        CircleOptions(
          geometry: LatLng(lat, lng),
          circleColor: '#0F6E56',
          circleRadius: 18,
        ),
      );
    } catch (_) {}
  }

  Widget _place(Session session, AppLocalizations l10n) {
    return Column(
      children: [
        BigIcon(
          icon: Icons.my_location,
          filled: true,
          label: l10n.useMyPlace,
          onTap: () async {
            final ok = await session.locate();
            if (!ok) {
              await Speaker.say(session.lang, l10n.tryAgain);
              return;
            }
            setState(() {
              _lat = session.lat;
              _lng = session.lng;
            });
            final lat = session.lat;
            final lng = session.lng;
            if (lat != null && lng != null) {
              await _map?.animateCamera(
                CameraUpdate.newLatLngZoom(LatLng(lat, lng), 17),
                duration: const Duration(milliseconds: 350),
              );
              await _pin(lat, lng);
            }
          },
        ),
        Expanded(
          child: MapLibreMap(
            styleString: 'https://tiles.openfreemap.org/styles/liberty',
            initialCameraPosition: CameraPosition(
              target: LatLng(
                _lat ?? session.lat ?? 20.5,
                _lng ?? session.lng ?? 78.9,
              ),
              zoom: 17,
            ),
            onMapCreated: (controller) => _map = controller,
            onStyleLoadedCallback: () {
              final lat = _lat ?? session.lat;
              final lng = _lng ?? session.lng;
              if (lat == null || lng == null) return;
              _map?.animateCamera(
                CameraUpdate.newLatLngZoom(LatLng(lat, lng), 17),
                duration: const Duration(milliseconds: 350),
              );
              unawaited(_pin(lat, lng));
            },
            onMapClick: (_, latLng) {
              setState(() {
                _lat = latLng.latitude;
                _lng = latLng.longitude;
              });
              unawaited(_pin(latLng.latitude, latLng.longitude));
            },
          ),
        ),
        SizedBox(
          height: 88,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(8),
            children: [
              for (final code in kLangs)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: LangTile(
                    code: code,
                    compact: true,
                    selected: _langs.contains(code),
                    onTap: () => setState(() {
                      if (_langs.contains(code) && _langs.length > 1) {
                        _langs.remove(code);
                      } else {
                        _langs.add(code);
                      }
                    }),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _media(Session session, AppLocalizations l10n) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Wrap(
          spacing: 8,
          children: [
            BigIcon(
              icon: Icons.photo_camera,
              label: l10n.camera,
              onTap: () => _pickImage(ImageSource.camera),
            ),
            BigIcon(
              icon: Icons.photo,
              label: l10n.addPhoto,
              onTap: () => _pickImage(ImageSource.gallery),
            ),
            BigIcon(
              icon: Icons.videocam,
              label: l10n.addVideo,
              onTap: () => _pickVideo(ImageSource.camera),
            ),
            BigIcon(
              icon: Icons.video_library,
              label: l10n.addVideo,
              onTap: () => _pickVideo(ImageSource.gallery),
            ),
            BigIcon(
              icon: _recording ? Icons.stop : Icons.mic,
              label: l10n.addAudio,
              filled: _recording,
              onTap: _toggleMic,
            ),
            BigIcon(
              icon: Icons.audio_file,
              label: l10n.addAudio,
              onTap: _pickAudioFile,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final id in _jobIds)
              if (session.outbox.job(id) case final item?)
                Stack(
                  children: [
                    if (item.kind == 'image')
                      LocalThumb(path: item.path, width: 72, height: 72)
                    else
                      SizedBox(
                        width: 72,
                        height: 72,
                        child: ColoredBox(
                          color: const Color(0xFFE7F2EE),
                          child: Icon(
                            item.kind == 'video' ? Icons.videocam : Icons.mic,
                          ),
                        ),
                      ),
                    if (item.status == 'failed')
                      Positioned.fill(
                        child: Center(
                          child: BigIcon(
                            icon: Icons.refresh,
                            label: l10n.tryAgain,
                            onTap: () => session.outbox.retryJob(item.id),
                          ),
                        ),
                      )
                    else if (item.status != 'ready')
                      const Positioned.fill(
                        child: Center(child: CircularProgressIndicator()),
                      ),
                  ],
                ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            for (final item in _library.where((item) => item.kind == 'image'))
              GestureDetector(
                onTap: () => setState(() {
                  if (_mediaIds.contains(item.id)) {
                    _mediaIds.remove(item.id);
                  } else {
                    _mediaIds.add(item.id);
                  }
                }),
                child: Stack(
                  children: [
                    NetImage(
                      url: item.url,
                      width: 72,
                      height: 72,
                      cacheLogical: 72,
                    ),
                    if (_mediaIds.contains(item.id))
                      const Icon(Icons.check_circle, color: Colors.white),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          children: [
            Text(
              '${l10n.addPhoto} ${_count(session, 'image')}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            Text(
              '${l10n.addVideo} ${_count(session, 'video')}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            Text(
              '${l10n.addAudio} ${_count(session, 'audio')}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ],
    );
  }
}
