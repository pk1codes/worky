import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'api.dart';
import 'talk_screen.dart';

final talkNav = GlobalKey<NavigatorState>();
final talkPing = ValueNotifier<String>('');

class TalkPush {
  static var _listening = false;
  static String? pending;

  static Future<void> listen() async {
    if (kIsWeb || _listening) return;
    _listening = true;
    FirebaseMessaging.onMessage.listen((message) {
      talkPing.value = message.data['pairId'] ?? '';
    });
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      open(message.data['pairId']);
    });
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    open(initial?.data['pairId']);
  }

  static void open(Object? pairId) {
    if (pairId is! String || pairId.isEmpty) return;
    pending = pairId;
    if (FirebaseAuth.instance.currentUser == null) return;
    final nav = talkNav.currentState;
    if (nav == null) return;
    pending = null;
    nav.push(MaterialPageRoute<void>(builder: (_) => TalkScreen(pairId: pairId)));
  }

  static void flush() => open(pending);

  static Future<void> allow(WorkyApi api) async {
    if (kIsWeb) return;
    await FirebaseMessaging.instance.requestPermission(alert: true, badge: true, sound: true);
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null || token.isEmpty) return;
    await api.savePush(token);
  }
}
