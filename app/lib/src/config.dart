import 'package:flutter/foundation.dart';

const bool kUseEmulator = bool.fromEnvironment('USE_EMULATOR', defaultValue: true);

const String kDebugEmail = String.fromEnvironment('DEBUG_EMAIL', defaultValue: 'worker@worky.test');

String get kHost => kIsWeb ? '127.0.0.1' : '10.0.2.2';

String get kApiBase => kUseEmulator
    ? 'http://$kHost:5001/worky-93fbc/us-central1/api'
    : 'https://us-central1-worky-93fbc.cloudfunctions.net/api';

const String kAppCheckSiteKey = String.fromEnvironment('APP_CHECK_SITE_KEY');
