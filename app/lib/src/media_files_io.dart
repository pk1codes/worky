import 'dart:io';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:light_compressor/light_compressor.dart';
import 'package:path_provider/path_provider.dart';

Future<Directory> _dir() async {
  final root = await getApplicationDocumentsDirectory();
  final folder = Directory('${root.path}/media');
  if (!await folder.exists()) await folder.create(recursive: true);
  return folder;
}

String _extOf(String source) {
  final slash = source.lastIndexOf('/');
  final name = slash == -1 ? source : source.substring(slash + 1);
  final dot = name.lastIndexOf('.');
  if (dot <= 0) return '';
  return name.substring(dot);
}

String _stemName(String source) {
  final slash = source.lastIndexOf('/');
  final name = slash == -1 ? source : source.substring(slash + 1);
  final dot = name.lastIndexOf('.');
  if (dot <= 0) return name;
  return name.substring(0, dot);
}

Future<String> localPath(String id, String ext) async {
  final folder = await _dir();
  return '${folder.path}/$id.$ext';
}

Future<String> stash(String id, String sourcePath) async {
  final folder = await _dir();
  final prefix = '${folder.path}/';
  if (sourcePath.startsWith(prefix)) return sourcePath;
  final dest = '${folder.path}/$id${_extOf(sourcePath)}';
  if (sourcePath != dest) await File(sourcePath).copy(dest);
  return dest;
}

Future<String> compressCapture(String kind, String path) async {
  if (kind == 'image') {
    final dot = path.lastIndexOf('.');
    final target = '${dot == -1 ? path : path.substring(0, dot)}.webp';
    final out = await FlutterImageCompress.compressAndGetFile(
      path,
      target,
      quality: 75,
      minWidth: 1080,
      minHeight: 1080,
      format: CompressFormat.webp,
    );
    if (out == null) throw StateError('compress');
    return out.path;
  }
  if (kind == 'video') {
    final result = await LightCompressor().compressVideo(
      path: path,
      videoQuality: VideoQuality.low,
      isMinBitrateCheckEnabled: false,
      video: Video(videoName: _stemName(path)),
      android: AndroidConfig(isSharedStorage: false),
      ios: IOSConfig(saveInGallery: false),
    );
    if (result is OnSuccess) return result.destinationPath;
    if (result is OnFailure) throw StateError(result.message);
    throw StateError('compress');
  }
  return path;
}

Future<int> byteLength(String path) => File(path).length();

Future<List<int>> readBytes(String path) => File(path).readAsBytes();

Stream<List<int>> openAt(String path, int start) => File(path).openRead(start);

Future<void> releasePath(String path) async {
  final file = File(path);
  if (await file.exists()) await file.delete();
}
