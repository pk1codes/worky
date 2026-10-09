import 'dart:convert';

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

class FeedPost {
  FeedPost({
    required this.id,
    required this.posterUrl,
    required this.daysAgo,
    required this.band,
    required this.langs,
    required this.hasVideo,
    required this.lat,
    required this.lng,
    required this.categoryId,
    required this.status,
    this.mediaIds = const [],
  });

  final String id;
  final String posterUrl;
  final int daysAgo;
  final String band;
  final List<String> langs;
  final bool hasVideo;
  final double lat;
  final double lng;
  final String categoryId;
  final String status;
  final List<String> mediaIds;

  factory FeedPost.fromJson(Map<String, dynamic> json) {
    return FeedPost(
      id: json['id'] as String,
      posterUrl: (json['posterUrl'] as String?) ?? '',
      daysAgo: (json['daysAgo'] as num?)?.toInt() ?? 0,
      band: (json['band'] as String?) ?? 'far',
      langs: ((json['langs'] as List?) ?? const []).cast<String>(),
      hasVideo: json['hasVideo'] == true,
      lat: (json['lat'] as num?)?.toDouble() ?? 0,
      lng: (json['lng'] as num?)?.toDouble() ?? 0,
      categoryId: (json['categoryId'] as String?) ?? '',
      status: (json['status'] as String?) ?? 'active',
      mediaIds: ((json['mediaIds'] as List?) ?? const []).cast<String>(),
    );
  }
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
    await _json('DELETE', '/v1/me');
  }

  Future<List<FeedCategory>?> feed({
    required String parentId,
    required double lat,
    required double lng,
    required String lang,
  }) async {
    final path =
        '/v1/feed?parentId=${Uri.encodeQueryComponent(parentId)}&lat=$lat&lng=$lng&lang=$lang';
    final json = await _json('GET', path, cache: true);
    if (json == null) return null;
    return ((json['categories'] as List?) ?? const [])
        .map(
          (row) => FeedCategory.fromJson(Map<String, dynamic>.from(row as Map)),
        )
        .toList();
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

  Future<List<FeedPost>> mine() async {
    final json = (await _json('GET', '/v1/me/posts'))!;
    return ((json['posts'] as List?) ?? const [])
        .map((row) => FeedPost.fromJson(Map<String, dynamic>.from(row as Map)))
        .toList();
  }

  Future<List<MediaItem>> library() async {
    final json = (await _json('GET', '/v1/me/media'))!;
    return ((json['media'] as List?) ?? const [])
        .map((row) => MediaItem.fromJson(Map<String, dynamic>.from(row as Map)))
        .toList();
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

  Future<void> hideCategory(String id, {required bool active}) async {
    await _json(
      'POST',
      '/v1/admin/categories/$id/hide',
      body: {'active': active},
    );
  }
}
