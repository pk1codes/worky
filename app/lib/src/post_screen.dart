import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:record/record.dart';

import '../l10n/app_localizations.dart';
import 'api.dart';
import 'browse_screen.dart';
import 'chrome.dart';
import 'langs.dart';
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
  final ImagePicker _picker = ImagePicker();
  final AudioRecorder _recorder = AudioRecorder();
  var _recording = false;
  var _busy = false;
  List<MediaItem> _library = [];
  MapLibreMapController? _map;

  @override
  void initState() {
    super.initState();
    FirebaseAnalytics.instance.logScreenView(screenName: 'post');
    _langs = {widget.edit?.langs.isNotEmpty == true ? widget.edit!.langs.first : 'hi'};
    _lat = widget.edit?.lat;
    _lng = widget.edit?.lng;
    _categoryId = widget.edit?.categoryId;
    _mediaIds.addAll(widget.edit?.mediaIds ?? const []);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final session = SessionHost.of(context);
      _langs = {if (widget.edit != null) ...widget.edit!.langs else session.lang ?? 'hi'};
      _lat ??= session.lat;
      _lng ??= session.lng;
      if (mounted) setState(() {});
      await Speaker.say(session.lang, AppLocalizations.of(context).post);
      try {
        final library = await session.api.library();
        if (mounted) setState(() => _library = library);
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    unawaited(_recorder.dispose());
    super.dispose();
  }

  Future<void> _upload(String kind, List<int> bytes, String type) async {
    final session = SessionHost.of(context);
    setState(() => _busy = true);
    try {
      final id = await session.api.upload(kind, bytes, type);
      if (mounted) setState(() => _mediaIds.add(id));
    } catch (_) {
      if (mounted) await Speaker.say(session.lang, AppLocalizations.of(context).tryAgain);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    final file = await _picker.pickImage(
      source: source,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 80,
    );
    if (file == null) return;
    await _upload('image', await file.readAsBytes(), 'image/jpeg');
  }

  Future<void> _pickVideo(ImageSource source) async {
    final file = await _picker.pickVideo(source: source, maxDuration: const Duration(seconds: 30));
    if (file == null) return;
    await _upload('video', await file.readAsBytes(), 'video/mp4');
  }

  Future<void> _toggleMic() async {
    if (_recording) {
      final path = await _recorder.stop();
      setState(() => _recording = false);
      if (path == null) return;
      final bytes = await XFile(path).readAsBytes();
      await _upload('audio', bytes, 'audio/wav');
      return;
    }
    if (!await _recorder.hasPermission()) return;
    await _recorder.start(const RecordConfig(encoder: AudioEncoder.wav), path: 'voice.wav');
    setState(() => _recording = true);
  }

  Future<void> _pickAudioFile() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3', 'wav', 'm4a'],
    );
    if (files.isEmpty) return;
    final file = files.first;
    final bytes = await file.readAsBytes();
    final type = (file.extension ?? '').toLowerCase() == 'wav' ? 'audio/wav' : 'audio/mpeg';
    await _upload('audio', bytes, type);
  }

  Future<void> _save() async {
    final session = SessionHost.of(context);
    if (_categoryId == null || _lat == null || _lng == null || _mediaIds.isEmpty) {
      await Speaker.say(session.lang, AppLocalizations.of(context).tryAgain);
      return;
    }
    setState(() => _busy = true);
    try {
      if (widget.edit == null) {
        await session.api.createPost(
          categoryId: _categoryId!,
          lat: _lat!,
          lng: _lng!,
          langs: _langs.toList(),
          mediaIds: _mediaIds,
        );
      } else {
        await session.api.updatePost(
          id: widget.edit!.id,
          categoryId: _categoryId!,
          lat: _lat!,
          lng: _lng!,
          langs: _langs.toList(),
          mediaIds: _mediaIds,
        );
      }
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) await Speaker.say(session.lang, AppLocalizations.of(context).tryAgain);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
              Row(
                children: [
                  BigIcon(
                    icon: Icons.arrow_back,
                    label: l10n.back,
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
                      child: Icon(Icons.circle, size: 14, color: i == _step ? const Color(0xFF0F6E56) : const Color(0xFFD5E5DF)),
                    ),
                  if (_step < 2)
                    BigIcon(
                      icon: Icons.arrow_forward,
                      onTap: _step == 0 && _categoryId == null
                          ? null
                          : () => setState(() => _step += 1),
                    )
                  else
                    BigIcon(icon: Icons.check, filled: true, label: l10n.save, onTap: _busy ? null : _save),
                ],
              ),
              if (_busy) const LinearProgressIndicator(),
              Expanded(child: _step == 0 ? _pickCategory() : _step == 1 ? _place(session, l10n) : _media(l10n)),
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
              await _map?.moveCamera(CameraUpdate.newLatLngZoom(LatLng(lat, lng), 15));
            }
          },
        ),
        Expanded(
          child: MapLibreMap(
            styleString: 'https://tiles.openfreemap.org/styles/liberty',
            initialCameraPosition: CameraPosition(
              target: LatLng(_lat ?? session.lat ?? 20.5, _lng ?? session.lng ?? 78.9),
              zoom: 15,
            ),
            onMapCreated: (controller) => _map = controller,
            onStyleLoadedCallback: () {
              final lat = _lat ?? session.lat;
              final lng = _lng ?? session.lng;
              if (lat == null || lng == null) return;
              _map?.moveCamera(CameraUpdate.newLatLngZoom(LatLng(lat, lng), 15));
            },
            onMapClick: (_, latLng) => setState(() {
              _lat = latLng.latitude;
              _lng = latLng.longitude;
            }),
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

  Widget _media(AppLocalizations l10n) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Wrap(
          spacing: 8,
          children: [
            BigIcon(icon: Icons.photo_camera, label: l10n.camera, onTap: () => _pickImage(ImageSource.camera)),
            BigIcon(icon: Icons.photo, label: l10n.addPhoto, onTap: () => _pickImage(ImageSource.gallery)),
            BigIcon(icon: Icons.videocam, label: l10n.addVideo, onTap: () => _pickVideo(ImageSource.camera)),
            BigIcon(icon: Icons.video_library, label: l10n.addVideo, onTap: () => _pickVideo(ImageSource.gallery)),
            BigIcon(
              icon: _recording ? Icons.stop : Icons.mic,
              label: l10n.addAudio,
              filled: _recording,
              onTap: _toggleMic,
            ),
            BigIcon(icon: Icons.audio_file, label: l10n.addAudio, onTap: _pickAudioFile),
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
                    Image.network(item.url, width: 72, height: 72, fit: BoxFit.cover),
                    if (_mediaIds.contains(item.id))
                      const Icon(Icons.check_circle, color: Colors.white),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text('${_mediaIds.length}', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
      ],
    );
  }
}
