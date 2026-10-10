import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _channel = MethodChannel('worky/permissions');

/// Ask for location, camera, and mic in one system prompt batch.
Future<void> requestSetupPermissions() async {
  if (kIsWeb) return;
  try {
    await _channel.invokeMethod<Object?>('requestSetup');
  } catch (_) {}
}
