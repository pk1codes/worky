import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'talk_screen.dart';

final talkNav = GlobalKey<NavigatorState>();
final talkPing = ValueNotifier<String>('');

class TalkPush {
  static var _listening = false;
  static String? pending;
  static String? front;
  static const _tokenKey = 'pushToken';
  static const _heads = MethodChannel('worky/heads');

  static Future<void> listen() async {
    if (kIsWeb || _listening) return;
    _listening = true;
    FirebaseMessaging.onMessage.listen((message) {
      final pair = message.data['pairId'] ?? '';
      talkPing.value = pair;
      if (pair.isNotEmpty && pair == front) return;
      final body = message.notification?.body ?? '';
      if (body.isEmpty) return;
      unawaited(_show(body));
    });
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      open(message.data['pairId']);
    });
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    open(initial?.data['pairId']);
  }

  static Future<void> _show(String body) async {
    try {
      await _heads.invokeMethod<void>('show', {'body': body});
    } catch (_) {}
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
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null || token.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_tokenKey) == token) return;
    await api.savePush(token);
    await prefs.setString(_tokenKey, token);
  }
}
