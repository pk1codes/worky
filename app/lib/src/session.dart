import 'dart:convert';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'config.dart';
import 'media_queue.dart';

class Session extends ChangeNotifier {
  Session(this.auth) : api = WorkyApi(auth) {
    outbox = MediaQueue(api, onPublished: dropFeed);
  }

  final FirebaseAuth auth;
  final WorkyApi api;
  late final MediaQueue outbox;
  SharedPreferences? _prefs;

  bool ready = false;
  String? lang;
  String? whatsapp;
  bool admin = false;
  User? user;
  double? lat;
  double? lng;
  static const feedTtl = Duration(hours: 1);
  final Map<String, List<FeedCategory>> feedCache = {};
  final Map<String, int> _feedAt = {};

  Future<void> boot() async {
    _prefs = await SharedPreferences.getInstance();
    await outbox.attach(_prefs!);
    lang = _prefs!.getString('lang');
    whatsapp = _prefs!.getString('whatsapp');
    final cachedLat = _prefs!.getDouble('lat');
    final cachedLng = _prefs!.getDouble('lng');
    if (cachedLat != null && cachedLng != null) {
      lat = cachedLat;
      lng = cachedLng;
    }
    if (kIsWeb && !kUseEmulator) {
      try {
        final result = await auth.getRedirectResult();
        user = result.user ?? auth.currentUser;
      } catch (_) {
        user = auth.currentUser;
      }
    } else {
      user = auth.currentUser;
    }
    ready = true;
    notifyListeners();
    if (user != null) outbox.kick();
    auth.authStateChanges().listen((next) async {
      user = next;
      await _analyticsUser(next?.uid);
      if (next != null) {
        outbox.kick();
        try {
          final me = await api.me();
          admin = me['admin'] == true;
          final serverWhatsapp = me['whatsapp'] as String?;
          if ((whatsapp == null || whatsapp!.isEmpty) &&
              serverWhatsapp != null) {
            whatsapp = serverWhatsapp;
            await _prefs!.setString('whatsapp', serverWhatsapp);
          }
          if (lang != null) {
            await api.saveMe(lang: lang, whatsapp: whatsapp);
          }
        } catch (_) {}
      } else {
        admin = false;
      }
      ready = true;
      notifyListeners();
    });
  }

  Future<void> setLang(String code) async {
    lang = code;
    notifyListeners();
    await _prefs?.setString('lang', code);
    if (user != null) {
      try {
        await api.saveMe(lang: code, whatsapp: whatsapp);
      } catch (_) {}
    }
  }

  Future<void> setWhatsapp(String value) async {
    final first = whatsapp == null || whatsapp!.isEmpty;
    whatsapp = value;
    notifyListeners();
    await _prefs?.setString('whatsapp', value);
    await api.saveMe(lang: lang, whatsapp: value);
    if (first && value.isNotEmpty) {
      try {
        await FirebaseAnalytics.instance.logSignUp(signUpMethod: 'whatsapp');
      } catch (_) {}
    }
  }

  Future<bool> locate() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return false;
    }
    late final Position position;
    try {
      position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          timeLimit: Duration(seconds: 10),
        ),
      );
    } catch (_) {
      return false;
    }
    lat = position.latitude;
    lng = position.longitude;
    await _prefs?.setDouble('lat', lat!);
    await _prefs?.setDouble('lng', lng!);
    notifyListeners();
    if (user != null) {
      try {
        await api.saveMe(lang: lang, whatsapp: whatsapp, lat: lat, lng: lng);
      } catch (_) {}
    }
    return true;
  }

  Future<void> signIn() async {
    if (kUseEmulator) {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final payload = base64Url
          .encode(
            utf8.encode(
              jsonEncode({
                'sub': kDebugEmail,
                'email': kDebugEmail,
                'email_verified': true,
                'aud': 'worky-93fbc',
                'iss': 'https://accounts.google.com',
                'iat': now,
                'exp': now + 3600,
              }),
            ),
          )
          .replaceAll('=', '');
      const header = 'eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0';
      await auth.signInWithCredential(
        GoogleAuthProvider.credential(
          idToken: '$header.$payload.',
          accessToken: 'debug',
        ),
      );
      return;
    }
    if (kIsWeb) {
      final provider = GoogleAuthProvider()
        ..setCustomParameters({'prompt': 'select_account'});
      await auth.signInWithPopup(provider);
      return;
    }
    final account = await GoogleSignIn.instance.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null) return;
    await auth.signInWithCredential(
      GoogleAuthProvider.credential(idToken: idToken),
    );
  }

  Future<void> trySilent() async {
    if (kUseEmulator || kIsWeb || auth.currentUser != null) return;
    final account = await GoogleSignIn.instance
        .attemptLightweightAuthentication();
    final idToken = account?.authentication.idToken;
    if (idToken == null) return;
    await auth.signInWithCredential(
      GoogleAuthProvider.credential(idToken: idToken),
    );
  }

  bool feedIsFresh(String key) {
    final at = _feedAt[key];
    if (at == null || !feedCache.containsKey(key)) return false;
    return DateTime.now().millisecondsSinceEpoch - at < feedTtl.inMilliseconds;
  }

  void rememberFeed(String key, List<FeedCategory> rows) {
    feedCache[key] = rows;
    _feedAt[key] = DateTime.now().millisecondsSinceEpoch;
  }

  void dropFeed() {
    feedCache.clear();
    _feedAt.clear();
  }

  Future<void> deleteAccount() async {
    await outbox.clear();
    await api.deleteMe();
    dropFeed();
    whatsapp = null;
    admin = false;
    await _prefs?.remove('whatsapp');
    await _analyticsUser(null);
    await auth.signOut();
    notifyListeners();
  }

  Future<void> _analyticsUser(String? uid) async {
    try {
      await FirebaseAnalytics.instance.setUserId(id: uid);
    } catch (_) {}
  }

  String cacheKey(String parentId) =>
      '$parentId|${lat?.toStringAsFixed(3)}|${lng?.toStringAsFixed(3)}|$lang';
}

class SessionHost extends InheritedWidget {
  const SessionHost({required this.session, required super.child, super.key});

  final Session session;

  static Session of(BuildContext context) {
    final host = context.dependOnInheritedWidgetOfExactType<SessionHost>();
    assert(host != null, 'SessionHost missing');
    return host!.session;
  }

  @override
  bool updateShouldNotify(SessionHost oldWidget) =>
      session != oldWidget.session;
}
