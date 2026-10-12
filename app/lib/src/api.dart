import 'dart:convert';
import 'dart:math' as math;

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import 'config.dart';

class ApiException implements Exception {
  ApiException(this.status);
  final int status;
}

class FinishException implements Exception {
  FinishException(this.status);
  final int status;
}

class UploadTicket {
  UploadTicket({
    required this.mediaId,
    required this.uploadUrl,
    required this.finishUrl,
  });

  final String mediaId;
  final String uploadUrl;
  final String finishUrl;
}

class Reach {
  Reach({required this.number, required this.at, required this.blocked});

  final String number;
  final int at;
  final bool blocked;

  factory Reach.fromJson(Map<String, dynamic> json) {
    return Reach(
      number: (json['number'] as String?) ?? '',
      at: (json['at'] as num?)?.toInt() ?? 0,
      blocked: json['blocked'] == true,
    );
  }
}

class FeedPost {
  FeedPost({
    required this.id,
    required this.posterUrl,
    this.thumbUrl = '',
    required this.daysAgo,
    required this.band,
    this.createdAt,
    this.km,
    required this.langs,
    required this.hasVideo,
    required this.lat,
    required this.lng,
    required this.categoryId,
    this.categoryPath = const [],
    required this.status,
    this.mediaIds = const [],
    this.contactsOpen = true,
    this.reaches = const [],
    this.country,
  });

  final String id;
  final String posterUrl;
  final String thumbUrl;
  final int daysAgo;
  final int? createdAt;
  final int? km;
  final String band;
  final List<String> langs;
  final bool hasVideo;
  final double lat;
  final double lng;
  final String categoryId;
  final List<String> categoryPath;
  final String status;
  final List<String> mediaIds;
  final bool contactsOpen;
  final List<Reach> reaches;
  final String? country;

  factory FeedPost.fromJson(Map<String, dynamic> json) {
    return FeedPost(
      id: json['id'] as String,
      posterUrl: (json['posterUrl'] as String?) ?? '',
      thumbUrl: (json['thumbUrl'] as String?) ?? '',
      daysAgo: (json['daysAgo'] as num?)?.toInt() ?? 0,
      createdAt: (json['createdAt'] as num?)?.toInt(),
      km: (json['km'] as num?)?.toInt(),
      band: (json['band'] as String?) ?? 'far',
      langs: ((json['langs'] as List?) ?? const []).cast<String>(),
      hasVideo: json['hasVideo'] == true,
      lat: (json['lat'] as num?)?.toDouble() ?? 0,
      lng: (json['lng'] as num?)?.toDouble() ?? 0,
      categoryId: (json['categoryId'] as String?) ?? '',
      categoryPath: ((json['categoryPath'] as List?) ?? const []).cast<String>(),
      status: (json['status'] as String?) ?? 'active',
      mediaIds: ((json['mediaIds'] as List?) ?? const []).cast<String>(),
      contactsOpen: json['contactsOpen'] != false,
      reaches: ((json['reaches'] as List?) ?? const [])
          .map((row) => Reach.fromJson(Map<String, dynamic>.from(row as Map)))
          .toList(),
      country: _isoCountry(json['country']),
    );
  }
}

String? _isoCountry(Object? raw) {
  if (raw is! String) return null;
  final code = raw.trim().toUpperCase();
  if (code.length != 2) return null;
  final a = code.codeUnitAt(0);
  final b = code.codeUnitAt(1);
  if (a < 65 || a > 90 || b < 65 || b > 90) return null;
  return code;
}

class FeedCategory {
  FeedCategory({
    required this.id,
    required this.name,
    required this.coverUrl,
    required this.kind,
    required this.posts,
  });

  final String id;
  final String name;
  final String coverUrl;
  final String kind;
  final List<FeedPost> posts;

  bool get isJob => kind == 'job';

  FeedCategory copyWith({List<FeedPost>? posts}) {
    return FeedCategory(
      id: id,
      name: name,
      coverUrl: coverUrl,
      kind: kind,
      posts: posts ?? this.posts,
    );
  }

  factory FeedCategory.fromJson(Map<String, dynamic> json) {
    return FeedCategory(
      id: json['id'] as String,
      name: (json['name'] as String?) ?? '',
      coverUrl: (json['coverUrl'] as String?) ?? '',
      kind: json['kind'] == 'job' ? 'job' : 'parent',
      posts: ((json['posts'] as List?) ?? const [])
          .map(
            (row) => FeedPost.fromJson(Map<String, dynamic>.from(row as Map)),
          )
          .toList(),
    );
  }
}

class FeedBox {
  FeedBox({
    required this.id,
    required this.south,
    required this.north,
    required this.west,
    required this.east,
    required this.included,
  });

  final String id;
  final double south;
  final double north;
  final double west;
  final double east;
  final bool included;

  factory FeedBox.fromJson(Map<String, dynamic> json) {
    return FeedBox(
      id: (json['id'] as String?) ?? '',
      south: (json['south'] as num?)?.toDouble() ?? 0,
      north: (json['north'] as num?)?.toDouble() ?? 0,
      west: (json['west'] as num?)?.toDouble() ?? 0,
      east: (json['east'] as num?)?.toDouble() ?? 0,
      included: json['in'] == true,
    );
  }
}

class FeedPage {
  FeedPage({required this.categories, required this.ring});

  final List<FeedCategory> categories;
  final List<FeedBox> ring;
}

class FeedHold {
  FeedHold(this.page, this.at);

  final FeedPage page;
  final int at;
}

double kmBetween(double aLat, double aLng, double bLat, double bLng) {
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

FeedPost placePost(FeedPost post, double lat, double lng) {
  final shown = math.max(2, kmBetween(lat, lng, post.lat, post.lng).round());
  return FeedPost(
    id: post.id,
    posterUrl: post.posterUrl,
    thumbUrl: post.thumbUrl,
    daysAgo: post.daysAgo,
    createdAt: post.createdAt,
    km: shown,
    band: shown < 15 ? 'mid' : 'far',
    langs: post.langs,
    hasVideo: post.hasVideo,
    lat: post.lat,
    lng: post.lng,
    categoryId: post.categoryId,
    categoryPath: post.categoryPath,
    status: post.status,
    mediaIds: post.mediaIds,
    contactsOpen: post.contactsOpen,
    reaches: post.reaches,
    country: post.country,
  );
}

List<FeedPost> nearestPosts(List<FeedPost> posts, double lat, double lng) {
  final placed = [for (final post in posts) placePost(post, lat, lng)];
  placed.sort((a, b) => (a.km ?? 0).compareTo(b.km ?? 0));
  if (placed.length <= 12) return placed;
  return placed.sublist(0, 12);
}

double closestBox(double lat, double lng, FeedBox box) {
  final cLat = math.min(box.north, math.max(box.south, lat));
  final cLng = math.min(box.east, math.max(box.west, lng));
  return kmBetween(lat, lng, cLat, cLng);
}

bool needsRing(FeedPage page, double lat, double lng) {
  for (final box in page.ring) {
    if (box.included) continue;
    final edge = closestBox(lat, lng, box);
    for (final row in page.categories) {
      if (!row.isJob) continue;
      if (row.posts.length < 12) return true;
      final distances = [for (final post in row.posts) kmBetween(lat, lng, post.lat, post.lng)]
        ..sort();
      if (edge < distances[11]) return true;
    }
  }
  return false;
}

class TalkPreview {
  TalkPreview({
    required this.id,
    required this.kind,
    required this.preview,
    required this.at,
    required this.unread,
    required this.closed,
  });

  final String id;
  final String kind;
  final String preview;
  final int at;
  final int unread;
  final bool closed;

  factory TalkPreview.fromJson(Map<String, dynamic> json) {
    return TalkPreview(
      id: (json['id'] as String?) ?? '',
      kind: (json['kind'] as String?) ?? 'text',
      preview: (json['preview'] as String?) ?? '',
      at: (json['at'] as num?)?.toInt() ?? 0,
      unread: (json['unread'] as num?)?.toInt() ?? 0,
      closed: json['closed'] == true,
    );
  }
}

class TalkMessage {
  TalkMessage({
    required this.id,
    required this.from,
    required this.at,
    required this.kind,
    this.text = '',
    this.url = '',
    this.durMs = 0,
    this.meetUrl = '',
    this.expiresAt = 0,
  });

  final String id;
  final String from;
  final int at;
  final String kind;
  final String text;
  final String url;
  final int durMs;
  final String meetUrl;
  final int expiresAt;

  bool get liveVideo =>
      meetUrl.isNotEmpty && expiresAt > DateTime.now().millisecondsSinceEpoch;

  factory TalkMessage.fromJson(Map<String, dynamic> json) {
    return TalkMessage(
      id: (json['id'] as String?) ?? '',
      from: (json['from'] as String?) ?? '',
      at: (json['at'] as num?)?.toInt() ?? 0,
      kind: (json['kind'] as String?) ?? 'text',
      text: (json['text'] as String?) ?? '',
      url: (json['url'] as String?) ?? '',
      durMs: (json['durMs'] as num?)?.toInt() ?? 0,
      meetUrl: (json['meetUrl'] as String?) ?? '',
      expiresAt: (json['expiresAt'] as num?)?.toInt() ?? 0,
    );
  }
}

class TalkThread {
  TalkThread({required this.pairId, required this.closed, required this.messages});

  final String pairId;
  final bool closed;
  final List<TalkMessage> messages;

  factory TalkThread.fromJson(Map<String, dynamic> json) {
    return TalkThread(
      pairId: (json['pairId'] as String?) ?? '',
      closed: json['closed'] == true,
      messages: ((json['messages'] as List?) ?? const [])
          .map((row) => TalkMessage.fromJson(Map<String, dynamic>.from(row as Map)))
          .toList(),
    );
  }
}

class MediaItem {
  MediaItem({required this.id, required this.kind, required this.url});
  final String id;
  final String kind;
  final String url;

  factory MediaItem.fromJson(Map<String, dynamic> json) {
    return MediaItem(
      id: json['id'] as String,
      kind: json['kind'] as String,
      url: json['url'] as String,
    );
  }
}

class WorkyApi {
  WorkyApi(this._auth);

  final FirebaseAuth _auth;
  final Map<String, String> _etags = {};

  Future<Map<String, String>> _headers({String? etag}) async {
    final user = _auth.currentUser;
    final token = await user?.getIdToken();
    final headers = <String, String>{'content-type': 'application/json'};
    if (token != null) headers['authorization'] = 'Bearer $token';
    if (!kUseEmulator) {
      try {
        final check = await FirebaseAppCheck.instance.getToken();
        if (check != null) headers['x-firebase-appcheck'] = check;
      } catch (_) {}
    }
    if (etag != null) headers['if-none-match'] = etag;
    return headers;
  }

  Future<Map<String, dynamic>?> _json(
    String method,
    String path, {
    Object? body,
    bool cache = false,
  }) async {
    final headers = await _headers(etag: cache ? _etags[path] : null);
    final uri = Uri.parse('$kApiBase$path');
    late http.Response response;
    if (method == 'GET') {
      response = await http.get(uri, headers: headers);
    } else if (method == 'POST') {
      response = await http.post(
        uri,
        headers: headers,
        body: jsonEncode(body ?? {}),
      );
    } else if (method == 'PUT') {
      response = await http.put(
        uri,
        headers: headers,
        body: jsonEncode(body ?? {}),
      );
    } else if (method == 'PATCH') {
      response = await http.patch(
        uri,
        headers: headers,
        body: jsonEncode(body ?? {}),
      );
    } else {
      response = await http.delete(uri, headers: headers);
    }
    if (response.statusCode == 304) return null;
    if (response.statusCode >= 300) throw ApiException(response.statusCode);
    final etag = response.headers['etag'];
    if (cache && etag != null) _etags[path] = etag;
    if (response.body.isEmpty) return {};
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> me() async => (await _json('GET', '/v1/me'))!;

  Future<void> saveMe({
    String? lang,
    String? whatsapp,
    double? lat,
    double? lng,
  }) async {
    final body = <String, dynamic>{'lang': lang, 'whatsapp': whatsapp};
    if (lat != null && lng != null) {
      body['lat'] = lat;
      body['lng'] = lng;
    }
    await _json('PUT', '/v1/me', body: body);
  }

  Future<void> deleteMe() async {
    String? cursor;
    for (var i = 0; i < 80; i += 1) {
      final path = cursor == null
          ? '/v1/me'
          : '/v1/me?cursor=${Uri.encodeQueryComponent(cursor)}';
      final json = (await _json('DELETE', path))!;
      if (json['ok'] == true) return;
      final next = json['cursor'] as String?;
      if (next == null || next == cursor) throw ApiException(500);
      cursor = next;
    }
    throw ApiException(500);
  }

  Future<FeedPage?> feed({
    required String parentId,
    required double lat,
    required double lng,
    required String lang,
    bool headersOnly = false,
    bool fresh = false,
  }) async {
    final cards = headersOnly ? '&cards=0' : '';
    final live = fresh ? '&fresh=1' : '';
    final path =
        '/v1/feed?parentId=${Uri.encodeQueryComponent(parentId)}&lat=$lat&lng=$lng&lang=$lang$cards$live';
    final json = await _json('GET', path, cache: true);
    if (json == null) return null;
    return FeedPage(
      categories: ((json['categories'] as List?) ?? const [])
          .map(
            (row) =>
                FeedCategory.fromJson(Map<String, dynamic>.from(row as Map)),
          )
          .toList(),
      ring: ((json['ring'] as List?) ?? const [])
          .map((row) => FeedBox.fromJson(Map<String, dynamic>.from(row as Map)))
          .toList(),
    );
  }

  Future<({List<MediaItem> media, bool mine, List<String> mediaIds})> post(
    String id,
  ) async {
    final json = (await _json('GET', '/v1/posts/$id'))!;
    final media = ((json['media'] as List?) ?? const [])
        .map((row) => MediaItem.fromJson(Map<String, dynamic>.from(row as Map)))
        .toList();
    return (
      media: media,
      mine: json['mine'] == true,
      mediaIds: ((json['mediaIds'] as List?) ?? const []).cast<String>(),
    );
  }

  Future<String> reveal(String id, String channel) async {
    final json = (await _json(
      'POST',
      '/v1/posts/$id/reveal',
      body: {'channel': channel},
    ))!;
    return json['url'] as String;
  }

  Future<({List<FeedPost> posts, List<TalkPreview> talks, String? cursor})>
  mine({String? cursor}) async {
    final path = cursor == null
        ? '/v1/me/posts'
        : '/v1/me/posts?cursor=${Uri.encodeQueryComponent(cursor)}';
    final json = (await _json('GET', path))!;
    final posts = ((json['posts'] as List?) ?? const [])
        .map((row) => FeedPost.fromJson(Map<String, dynamic>.from(row as Map)))
        .toList();
    final talks = ((json['talks'] as List?) ?? const [])
        .map((row) => TalkPreview.fromJson(Map<String, dynamic>.from(row as Map)))
        .toList();
    return (posts: posts, talks: talks, cursor: json['cursor'] as String?);
  }

  Future<({List<MediaItem> media, String? cursor})> libraryPage({
    String? cursor,
  }) async {
    final path = cursor == null
        ? '/v1/me/media'
        : '/v1/me/media?cursor=${Uri.encodeQueryComponent(cursor)}';
    final json = (await _json('GET', path))!;
    return (
      media: ((json['media'] as List?) ?? const [])
          .map((row) => MediaItem.fromJson(Map<String, dynamic>.from(row as Map)))
          .toList(),
      cursor: json['cursor'] as String?,
    );
  }

  Future<List<MediaItem>> library() async {
    final rows = <MediaItem>[];
    String? cursor;
    for (var i = 0; i < 3; i += 1) {
      final page = await libraryPage(cursor: cursor);
      rows.addAll(page.media);
      cursor = page.cursor;
      if (cursor == null) break;
    }
    return rows;
  }

  Future<UploadTicket> openUpload({
    required String kind,
    required int bytes,
    required String contentType,
  }) async {
    final ticket = (await _json(
      'POST',
      '/v1/media/upload-url',
      body: {'kind': kind, 'bytes': bytes, 'contentType': contentType},
    ))!;
    final uploadUrl = ticket['uploadUrl'] as String? ?? '';
    final finishUrl = ticket['finishUrl'] as String? ?? '';
    if (uploadUrl.isEmpty || finishUrl.isEmpty) throw ApiException(500);
    return UploadTicket(
      mediaId: ticket['mediaId'] as String,
      uploadUrl: uploadUrl,
      finishUrl: finishUrl,
    );
  }

  Future<void> putStream(
    String uploadUrl,
    int length,
    Stream<List<int>> Function(int start) open, {
    bool resume = false,
  }) async {
    final uri = Uri.parse(uploadUrl);
    final client = http.Client();
    try {
      var start = 0;
      if (resume) start = await _uploaded(client, uri, length);
      if (start >= length) return;
      final request = http.StreamedRequest('PUT', uri);
      request.contentLength = length - start;
      request.headers['content-range'] = 'bytes $start-${length - 1}/$length';
      final sent = client.send(request);
      await request.sink.addStream(open(start));
      await request.sink.close();
      final response = await sent;
      final code = response.statusCode;
      await response.stream.drain();
      if (code != 200 && code != 201) throw ApiException(code);
    } finally {
      client.close();
    }
  }

  Future<int> _uploaded(http.Client client, Uri uri, int length) async {
    final probe = http.Request('PUT', uri);
    probe.headers['content-range'] = 'bytes */$length';
    probe.bodyBytes = const [];
    final response = await client.send(probe);
    final code = response.statusCode;
    final range = response.headers['range'];
    await response.stream.drain();
    if (code == 200 || code == 201) return length;
    if (code != 308) throw ApiException(code);
    final match = RegExp(r'bytes=0-(\d+)').firstMatch(range ?? '');
    if (match == null) return 0;
    return int.parse(match.group(1)!) + 1;
  }

  Future<void> finishUpload(String finishUrl) async {
    final headers = await _headers();
    final response = await http.put(
      Uri.parse(finishUrl),
      headers: headers,
      body: '{}',
    );
    if (response.statusCode >= 300) throw FinishException(response.statusCode);
  }

  Future<String> createPost({
    required String categoryId,
    required double lat,
    required double lng,
    required List<String> langs,
    required List<String> mediaIds,
  }) async {
    final json = (await _json(
      'POST',
      '/v1/posts',
      body: {
        'categoryId': categoryId,
        'lat': lat,
        'lng': lng,
        'langs': langs,
        'mediaIds': mediaIds,
      },
    ))!;
    return json['id'] as String;
  }

  Future<void> updatePost({
    required String id,
    required String categoryId,
    required double lat,
    required double lng,
    required List<String> langs,
    required List<String> mediaIds,
  }) async {
    await _json(
      'PATCH',
      '/v1/posts/$id',
      body: {
        'categoryId': categoryId,
        'lat': lat,
        'lng': lng,
        'langs': langs,
        'mediaIds': mediaIds,
      },
    );
  }

  Future<void> pause(String id, bool paused) async {
    await _json('POST', '/v1/posts/$id/pause', body: {'paused': paused});
  }

  Future<void> blockIncoming(String id, bool blocked) async {
    await _json('POST', '/v1/posts/$id/block', body: {'blocked': blocked});
  }

  Future<void> blockNumber(String postId, String number, bool blocked) async {
    await _json(
      'POST',
      '/v1/me/blocks',
      body: {'postId': postId, 'number': number, 'blocked': blocked},
    );
  }

  Future<void> deletePost(String id) async {
    await _json('DELETE', '/v1/posts/$id');
  }

  Future<List<Map<String, dynamic>>> adminCategories() async {
    final json = (await _json('GET', '/v1/admin/categories'))!;
    return ((json['categories'] as List?) ?? const [])
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<void> saveCategory({
    String? id,
    required String parentId,
    required String kind,
    required Map<String, String> names,
    required String coverMediaId,
    required int sort,
  }) async {
    final body = {
      'parentId': parentId,
      'kind': kind,
      'names': names,
      'coverMediaId': coverMediaId,
      'sort': sort,
    };
    if (id == null) {
      await _json('POST', '/v1/admin/categories', body: body);
    } else {
      await _json('PATCH', '/v1/admin/categories/$id', body: body);
    }
  }

  Future<void> savePush(String token) async {
    await _json('PUT', '/v1/me/push', body: {'token': token});
  }

  Future<TalkThread> talkForPost(String postId) async {
    final json = (await _json('GET', '/v1/posts/$postId/talk'))!;
    return TalkThread.fromJson(json);
  }

  Future<TalkThread> talk(String pairId) async {
    final json = (await _json('GET', '/v1/talks/$pairId'))!;
    return TalkThread.fromJson(json);
  }

  Future<TalkThread> sendTalk({
    String? postId,
    String? pairId,
    String? text,
    String? mediaId,
    int? durMs,
  }) async {
    final body = <String, dynamic>{};
    if (text != null) body['text'] = text;
    if (mediaId != null) {
      body['mediaId'] = mediaId;
      body['durMs'] = durMs ?? 0;
    }
    final path = (pairId == null || pairId.isEmpty)
        ? '/v1/posts/$postId/talk'
        : '/v1/talks/$pairId';
    final json = (await _json('POST', path, body: body))!;
    return TalkThread(
      pairId: (json['pairId'] as String?) ?? pairId ?? '',
      closed: false,
      messages: [
        TalkMessage.fromJson(Map<String, dynamic>.from(json['message'] as Map)),
      ],
    );
  }

  Future<TalkThread> startVideo({
    String? postId,
    String? pairId,
    required String accessToken,
  }) async {
    final path = (pairId == null || pairId.isEmpty)
        ? '/v1/posts/$postId/talk/video'
        : '/v1/talks/$pairId/video';
    final json = (await _json('POST', path, body: {'accessToken': accessToken}))!;
    return TalkThread(
      pairId: (json['pairId'] as String?) ?? pairId ?? '',
      closed: false,
      messages: [
        TalkMessage.fromJson(Map<String, dynamic>.from(json['message'] as Map)),
      ],
    );
  }

  Future<void> closeTalk(String pairId) async {
    await _json('POST', '/v1/talks/$pairId/block');
  }

  Future<void> hideCategory(String id, {required bool active}) async {
    await _json(
      'POST',
      '/v1/admin/categories/$id/hide',
      body: {'active': active},
    );
  }
}
