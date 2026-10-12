import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import 'api.dart';
import 'chrome.dart';
import 'media_files.dart' if (dart.library.io) 'media_files_io.dart' as files;
import 'session.dart';
import 'talk_push.dart';

class TalkScreen extends StatefulWidget {
  const TalkScreen({this.postId, this.pairId, super.key});

  final String? postId;
  final String? pairId;

  @override
  State<TalkScreen> createState() => _TalkScreenState();
}

class _TalkScreenState extends State<TalkScreen> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  final _recorder = AudioRecorder();
  final _player = AudioPlayer();
  List<TalkMessage> _messages = [];
  String? _pairId;
  var _closed = false;
  var _loading = true;
  var _sending = false;
  var _recording = false;
  var _recordMs = 0;
  Timer? _tick;
  String? _playing;

  @override
  void initState() {
    super.initState();
    _pairId = widget.pairId;
    FirebaseAnalytics.instance.logScreenView(screenName: 'talk');
    talkPing.addListener(_onPing);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!kIsWeb) {
        try {
          await TalkPush.allow(SessionHost.of(context).api);
        } catch (_) {}
      }
      await _load();
    });
  }

  void _onPing() {
    if (!mounted || talkPing.value != _pairId) return;
    unawaited(_load());
  }

  @override
  void dispose() {
    talkPing.removeListener(_onPing);
    _tick?.cancel();
    _text.dispose();
    _scroll.dispose();
    unawaited(_recorder.dispose());
    unawaited(_player.dispose());
    super.dispose();
  }

  Future<void> _load() async {
    final session = SessionHost.of(context);
    try {
      final thread = _pairId == null || _pairId!.isEmpty
          ? await session.api.talkForPost(widget.postId!)
          : await session.api.talk(_pairId!);
      if (!mounted) return;
      setState(() {
        if (thread.pairId.isNotEmpty) _pairId = thread.pairId;
        _closed = thread.closed;
        _messages = thread.messages;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _fail() async {
    if (!mounted) return;
    final session = SessionHost.of(context);
    await Speaker.say(session.lang, AppLocalizations.of(context).tryAgain);
  }

  Future<void> _sendText() async {
    final text = _text.text.trim();
    if (text.isEmpty || _sending || _closed) return;
    setState(() => _sending = true);
    try {
      final sent = await _post(text: text);
      if (!mounted) return;
      _text.clear();
      setState(() {
        _pairId = sent.pairId;
        _messages = [..._messages, ...sent.messages];
      });
    } catch (_) {
      await _fail();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<TalkThread> _post({String? text, String? mediaId, int? durMs}) {
    final api = SessionHost.of(context).api;
    return api.sendTalk(
      postId: widget.postId,
      pairId: _pairId,
      text: text,
      mediaId: mediaId,
      durMs: durMs,
    );
  }

  Future<void> _toggleMic() async {
    if (_sending || _closed) return;
    if (_recording) {
      await _finishMic();
      return;
    }
    if (!await _recorder.hasPermission()) return;
    if (!mounted) return;
    final session = SessionHost.of(context);
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
    _recordMs = 0;
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(seconds: 1), (timer) {
      _recordMs += 1000;
      if (_recordMs >= 60000) {
        timer.cancel();
        unawaited(_finishMic());
      }
      if (mounted) setState(() {});
    });
    if (mounted) setState(() => _recording = true);
  }

  Future<void> _finishMic() async {
    _tick?.cancel();
    final path = await _recorder.stop();
    final ms = _recordMs;
    if (!mounted) return;
    setState(() => _recording = false);
    if (path == null) return;
    final localId = 'local-voice-${DateTime.now().millisecondsSinceEpoch}';
    final session = SessionHost.of(context);
    setState(() {
      _sending = true;
      _messages = [
        ..._messages,
        TalkMessage(
          id: localId,
          from: session.user?.uid ?? '',
          at: DateTime.now().millisecondsSinceEpoch,
          kind: 'voice',
          durMs: ms,
        ),
      ];
    });
    final api = session.api;
    try {
      final length = await files.byteLength(path);
      final ticket = await api.openUpload(
        kind: 'voice',
        bytes: length,
        contentType: 'audio/mp4',
      );
      await api.putStream(
        ticket.uploadUrl,
        length,
        (start) => files.openAt(path, start),
      );
      await api.finishUpload(ticket.finishUrl);
      if (!mounted) return;
      final sent = await _post(mediaId: ticket.mediaId, durMs: ms);
      if (!mounted) return;
      setState(() {
        _pairId = sent.pairId;
        _messages = [
          for (final message in _messages)
            if (message.id != localId) message,
          ...sent.messages,
        ];
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _messages = [
            for (final message in _messages)
              if (message.id != localId) message,
          ];
        });
      }
      await _fail();
    } finally {
      if (mounted) setState(() => _sending = false);
      unawaited(files.releasePath(path));
    }
  }

  TalkMessage? _liveMeet() {
    for (var i = _messages.length - 1; i >= 0; i -= 1) {
      final message = _messages[i];
      if (message.liveVideo) return message;
    }
    return null;
  }

  Future<bool> _acceptVideoNotice() async {
    final l10n = AppLocalizations.of(context);
    final allow = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: SingleChildScrollView(child: Text(l10n.videoNotice)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.back),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.accept),
          ),
        ],
      ),
    );
    return allow == true;
  }

  Future<void> _video() async {
    if (_sending || _closed || kIsWeb) return;
    final live = _liveMeet();
    if (live != null) {
      await launchUrl(
        Uri.parse(live.meetUrl),
        mode: LaunchMode.externalApplication,
      );
      return;
    }
    final session = SessionHost.of(context);
    var token = await session.calendarToken();
    if (!mounted) return;
    if (token == null || token.isEmpty) {
      if (!await _acceptVideoNotice() || !mounted) return;
      try {
        token = await session.calendarToken(prompt: true);
      } catch (_) {
        if (mounted) await _fail();
        return;
      }
    }
    if (!mounted) return;
    if (token == null || token.isEmpty) {
      await _fail();
      return;
    }
    setState(() => _sending = true);
    try {
      final sent = await session.api.startVideo(
        postId: widget.postId,
        pairId: _pairId,
        accessToken: token,
      );
      if (!mounted) return;
      setState(() {
        _pairId = sent.pairId;
        final known = {for (final message in _messages) message.id};
        _messages = [
          ..._messages,
          for (final message in sent.messages)
            if (!known.contains(message.id)) message,
        ];
      });
      final url = sent.messages.isEmpty ? '' : sent.messages.last.meetUrl;
      if (url.isNotEmpty) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      await _fail();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _play(TalkMessage message) async {
    if (_playing == message.id) {
      await _player.stop();
      if (mounted) setState(() => _playing = null);
      return;
    }
    await _player.stop();
    await _player.play(UrlSource(message.url));
    if (mounted) setState(() => _playing = message.id);
    _player.onPlayerComplete.first.then((_) {
      if (mounted && _playing == message.id) setState(() => _playing = null);
    });
  }

  Future<void> _block() async {
    final id = _pairId;
    if (id == null || id.isEmpty) return;
    try {
      await SessionHost.of(context).api.closeTalk(id);
      if (mounted) setState(() => _closed = true);
    } catch (_) {
      await _fail();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final mine = SessionHost.of(context).user?.uid;
    return Paged(
      page: 7,
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
                    Expanded(
                      child: Text(
                        l10n.workyTalk,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF16332C),
                        ),
                      ),
                    ),
                    BigIcon(
                      icon: Icons.block,
                      label: _closed ? l10n.blocked : l10n.block,
                      compact: true,
                      filled: _closed,
                      onTap: _closed ? null : _block,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView.builder(
                        controller: _scroll,
                        reverse: true,
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final message =
                              _messages[_messages.length - 1 - index];
                          return _Bubble(
                            message: message,
                            mine: message.from == mine,
                            playing: _playing == message.id,
                            onPlay: () => _play(message),
                            join: l10n.joinVideo,
                            video: l10n.videoCall,
                            voice: l10n.addAudio,
                          );
                        },
                      ),
              ),
              if (_closed)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    l10n.blocked,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                )
              else
                _Composer(
                  controller: _text,
                  hint: l10n.typeMessage,
                  sending: _sending,
                  recording: _recording,
                  seconds: _recordMs ~/ 1000,
                  showVideo: !kIsWeb,
                  onSend: () {
                    if (_recording) {
                      unawaited(_finishMic());
                      return;
                    }
                    unawaited(_sendText());
                  },
                  onMic: _toggleMic,
                  onVideo: _video,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.message,
    required this.mine,
    required this.playing,
    required this.onPlay,
    required this.join,
    required this.video,
    required this.voice,
  });

  final TalkMessage message;
  final bool mine;
  final bool playing;
  final VoidCallback onPlay;
  final String join;
  final String video;
  final String voice;

  @override
  Widget build(BuildContext context) {
    final bg = mine ? const Color(0xFF0F6E56) : const Color(0xFFE7F2EE);
    final fg = mine ? Colors.white : const Color(0xFF16332C);
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: const BoxConstraints(maxWidth: 280),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(18),
        ),
        child: message.kind == 'text'
            ? Text(message.text, style: TextStyle(color: fg, fontSize: 16))
            : message.kind == 'voice'
            ? InkWell(
                onTap: message.url.isEmpty ? null : onPlay,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(playing ? Icons.stop : Icons.play_arrow, color: fg),
                    const SizedBox(width: 6),
                    Text(
                      '$voice ${message.durMs ~/ 1000}s',
                      style: TextStyle(color: fg, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              )
            : message.liveVideo
            ? InkWell(
                onTap: () => launchUrl(
                  Uri.parse(message.meetUrl),
                  mode: LaunchMode.externalApplication,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.videocam, color: fg),
                    const SizedBox(width: 6),
                    Text(
                      join,
                      style: TextStyle(color: fg, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              )
            : Text(video, style: TextStyle(color: fg.withValues(alpha: 0.7))),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.hint,
    required this.sending,
    required this.recording,
    required this.seconds,
    required this.showVideo,
    required this.onSend,
    required this.onMic,
    required this.onVideo,
  });

  final TextEditingController controller;
  final String hint;
  final bool sending;
  final bool recording;
  final int seconds;
  final bool showVideo;
  final VoidCallback onSend;
  final VoidCallback onMic;
  final VoidCallback onVideo;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              decoration: InputDecoration(
                hintText: recording ? '${seconds}s' : hint,
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          BigIcon(
            icon: recording ? Icons.stop : Icons.mic,
            filled: recording,
            compact: true,
            extent: 52,
            onTap: sending ? null : onMic,
          ),
          if (showVideo)
            BigIcon(
              icon: Icons.videocam,
              compact: true,
              extent: 52,
              onTap: sending ? null : onVideo,
            ),
          BigIcon(
            icon: Icons.send,
            filled: true,
            compact: true,
            extent: 52,
            onTap: sending ? null : onSend,
          ),
        ],
      ),
    );
  }
}
