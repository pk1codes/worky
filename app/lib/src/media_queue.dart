import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'media_files.dart' if (dart.library.io) 'media_files_io.dart' as files;

class MediaJob {
  MediaJob({
    required this.id,
    required this.kind,
    required this.path,
    this.status = 'queued',
    this.mediaId,
    this.uploadUrl,
    this.finishUrl,
    this.compressed = false,
    this.resume = false,
    List<String>? owned,
  }) : owned = owned ?? <String>[];

  final String id;
  final String kind;
  String path;
  String status;
  String? mediaId;
  String? uploadUrl;
  String? finishUrl;
  bool compressed;
  bool resume;
  final List<String> owned;

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind,
    'path': path,
    'status': status,
    'mediaId': mediaId,
    'uploadUrl': uploadUrl,
    'finishUrl': finishUrl,
    'compressed': compressed,
    'resume': resume,
    'owned': owned,
  };

  factory MediaJob.fromJson(Map<String, dynamic> json) {
    return MediaJob(
      id: json['id'] as String,
      kind: json['kind'] as String,
      path: json['path'] as String? ?? '',
      status: json['status'] as String? ?? 'queued',
      mediaId: json['mediaId'] as String?,
      uploadUrl: json['uploadUrl'] as String?,
      finishUrl: json['finishUrl'] as String?,
      compressed: json['compressed'] == true,
      resume: json['resume'] == true,
      owned: ((json['owned'] as List?) ?? const []).cast<String>(),
    );
  }
}

class OutboxDraft {
  OutboxDraft({
    required this.id,
    required this.categoryId,
    required this.lat,
    required this.lng,
    required this.langs,
    required this.libraryIds,
    required this.jobIds,
    this.postId,
    this.failed = false,
  });

  final String id;
  final String? postId;
  final String categoryId;
  final double lat;
  final double lng;
  final List<String> langs;
  final List<String> libraryIds;
  final List<String> jobIds;
  bool failed;

  Map<String, Object?> toJson() => {
    'id': id,
    'postId': postId,
    'categoryId': categoryId,
    'lat': lat,
    'lng': lng,
    'langs': langs,
    'libraryIds': libraryIds,
    'jobIds': jobIds,
    'failed': failed,
  };

  factory OutboxDraft.fromJson(Map<String, dynamic> json) {
    return OutboxDraft(
      id: json['id'] as String,
      postId: json['postId'] as String?,
      categoryId: json['categoryId'] as String? ?? '',
      lat: (json['lat'] as num?)?.toDouble() ?? 0,
      lng: (json['lng'] as num?)?.toDouble() ?? 0,
      langs: ((json['langs'] as List?) ?? const []).cast<String>(),
      libraryIds: ((json['libraryIds'] as List?) ?? const []).cast<String>(),
      jobIds: ((json['jobIds'] as List?) ?? const []).cast<String>(),
      failed: json['failed'] == true,
    );
  }
}

class MediaQueue extends ChangeNotifier {
  MediaQueue(this._api);

  final WorkyApi _api;
  SharedPreferences? _prefs;
  final List<MediaJob> jobs = [];
  final List<OutboxDraft> drafts = [];
  var _pumping = false;
  var _seq = 0;

  String freshId() {
    _seq += 1;
    return '${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}$_seq';
  }

  MediaJob? job(String id) {
    for (final item in jobs) {
      if (item.id == id) return item;
    }
    return null;
  }

  Future<String> localPath(String id, String ext) => files.localPath(id, ext);

  Future<void> attach(SharedPreferences prefs) async {
    _prefs = prefs;
    jobs
      ..clear()
      ..addAll(_readList(prefs, 'outbox_jobs').map(MediaJob.fromJson));
    drafts
      ..clear()
      ..addAll(_readList(prefs, 'outbox_drafts').map(OutboxDraft.fromJson));
    for (final item in jobs) {
      if (item.status == 'compressing' || item.status == 'uploading') {
        item.status = 'queued';
      }
    }
    notifyListeners();
  }

  void addFile({
    required String id,
    required String kind,
    required String path,
    bool ownsPath = false,
  }) {
    final item = MediaJob(id: id, kind: kind, path: path);
    if (ownsPath) item.owned.add(path);
    jobs.add(item);
    unawaited(_store());
    kick();
  }

  void saveDraft({
    String? postId,
    required String categoryId,
    required double lat,
    required double lng,
    required List<String> langs,
    required List<String> libraryIds,
    required List<String> jobIds,
  }) {
    drafts.add(
      OutboxDraft(
        id: freshId(),
        postId: postId,
        categoryId: categoryId,
        lat: lat,
        lng: lng,
        langs: langs,
        libraryIds: libraryIds,
        jobIds: jobIds,
      ),
    );
    unawaited(_store());
    kick();
  }

  void retryDraft(String id) {
    OutboxDraft? draft;
    for (final item in drafts) {
      if (item.id == id) draft = item;
    }
    if (draft == null) return;
    draft.failed = false;
    for (final jobId in draft.jobIds) {
      final item = job(jobId);
      if (item != null && item.status == 'failed') item.status = 'queued';
    }
    unawaited(_store());
    kick();
  }

  void retryJob(String id) {
    final item = job(id);
    if (item == null || item.status != 'failed') return;
    item.status = 'queued';
    for (final draft in drafts) {
      if (draft.jobIds.contains(id)) draft.failed = false;
    }
    unawaited(_store());
    kick();
  }

  Future<void> clear() async {
    for (final item in jobs) {
      for (final path in item.owned.toSet()) {
        await files.releasePath(path);
      }
    }
    jobs.clear();
    drafts.clear();
    await _store();
  }

  void kick() {
    if (_prefs == null) return;
    unawaited(_pump());
  }

  Future<void> _pump() async {
    if (_pumping) return;
    _pumping = true;
    try {
      while (true) {
        final next = _nextQueued();
        if (next == null) {
          await _publishAll();
          break;
        }
        await _run(next);
        await _publishAll();
      }
    } finally {
      _pumping = false;
      if (_nextQueued() != null) unawaited(_pump());
    }
  }

  MediaJob? _nextQueued() {
    for (final item in jobs) {
      if (item.status == 'queued') return item;
    }
    return null;
  }

  Future<void> _run(MediaJob item) async {
    try {
      if (!item.compressed) {
        item.status = 'compressing';
        await _store();
        final stashed = await files.stash(item.id, item.path);
        if (stashed != item.path) {
          item.owned.add(stashed);
          item.path = stashed;
        }
        final out = await files.compressCapture(item.kind, item.path);
        if (out != item.path) {
          await files.releasePath(item.path);
          item.owned.remove(item.path);
          item.owned.add(out);
          item.path = out;
        }
        item.compressed = true;
      }
      item.status = 'uploading';
      await _store();
      final length = await files.byteLength(item.path);
      final type = contentTypeFor(item.kind, item.path);
      if (item.uploadUrl == null || item.finishUrl == null) {
        final ticket = await _api.openUpload(
          kind: item.kind,
          bytes: length,
          contentType: type,
        );
        item.mediaId = ticket.mediaId;
        item.uploadUrl = ticket.uploadUrl;
        item.finishUrl = ticket.finishUrl;
        await _store();
      }
      await _api.putStream(
        item.uploadUrl!,
        length,
        (start) => files.openAt(item.path, start),
        resume: item.resume,
      );
      await _api.finishUpload(item.finishUrl!);
      item.status = 'ready';
      item.resume = false;
      await _store();
    } on FinishException {
      item.uploadUrl = null;
      item.finishUrl = null;
      item.mediaId = null;
      item.resume = false;
      item.status = 'failed';
      await _store();
    } catch (_) {
      item.resume = item.uploadUrl != null;
      item.status = 'failed';
      await _store();
    }
  }

  Future<void> _publishAll() async {
    for (final draft in [...drafts]) {
      if (draft.failed) continue;
      final mine = <MediaJob>[];
      var missing = false;
      for (final id in draft.jobIds) {
        final item = job(id);
        if (item == null) {
          missing = true;
          break;
        }
        mine.add(item);
      }
      if (missing) {
        draft.failed = true;
        await _store();
        continue;
      }
      if (mine.any((item) => item.status != 'ready' || item.mediaId == null)) {
        continue;
      }
      final ids = <String>[
        ...draft.libraryIds,
        for (final item in mine) item.mediaId!,
      ];
      try {
        if (draft.postId == null) {
          await _api.createPost(
            categoryId: draft.categoryId,
            lat: draft.lat,
            lng: draft.lng,
            langs: draft.langs,
            mediaIds: ids,
          );
        } else {
          await _api.updatePost(
            id: draft.postId!,
            categoryId: draft.categoryId,
            lat: draft.lat,
            lng: draft.lng,
            langs: draft.langs,
            mediaIds: ids,
          );
        }
        for (final item in mine) {
          for (final path in {...item.owned, item.path}) {
            await files.releasePath(path);
          }
        }
        drafts.remove(draft);
        jobs.removeWhere((item) => draft.jobIds.contains(item.id));
        await _store();
      } catch (_) {
        draft.failed = true;
        await _store();
      }
    }
  }

  Future<void> _store() async {
    final prefs = _prefs;
    if (prefs != null) {
      await prefs.setString(
        'outbox_jobs',
        jsonEncode(jobs.map((item) => item.toJson()).toList()),
      );
      await prefs.setString(
        'outbox_drafts',
        jsonEncode(drafts.map((item) => item.toJson()).toList()),
      );
    }
    notifyListeners();
  }

  List<Map<String, dynamic>> _readList(SharedPreferences prefs, String key) {
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
    } catch (_) {
      return const [];
    }
  }
}

String contentTypeFor(String kind, String path) {
  final dot = path.lastIndexOf('.');
  final ext = (dot == -1 ? '' : path.substring(dot + 1)).toLowerCase();
  if (kind == 'image') {
    if (ext == 'png') return 'image/png';
    if (ext == 'webp') return 'image/webp';
    return 'image/jpeg';
  }
  if (kind == 'video') return 'video/mp4';
  if (ext == 'wav') return 'audio/wav';
  if (ext == 'm4a' || ext == 'mp4' || ext == 'aac') return 'audio/mp4';
  return 'audio/mpeg';
}
