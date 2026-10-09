import 'package:image_picker/image_picker.dart';

Future<String> localPath(String id, String ext) async => '$id.$ext';

Future<String> stash(String id, String sourcePath) async => sourcePath;

Future<String> compressCapture(String kind, String path) async => path;

Future<int> byteLength(String path) => XFile(path).length();

Stream<List<int>> openAt(String path, int start) => XFile(path).openRead(start);

Future<void> releasePath(String path) async {}
