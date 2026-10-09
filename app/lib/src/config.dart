import 'package:flutter/foundation.dart';

const bool kUseEmulator = bool.fromEnvironment('USE_EMULATOR', defaultValue: true);

String get kHost => kIsWeb ? '127.0.0.1' : '10.0.2.2';

String get kApiBase => 'http://$kHost:5001/worky-93fbc/us-central1/api';
