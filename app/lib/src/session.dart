import 'dart:async';
import 'dart:convert';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:phone_numbers_parser/phone_numbers_parser.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'config.dart';
import 'media_queue.dart';

bool validPhone(String value) {
  try {
    return PhoneNumber.parse(value).isValid();
  } catch (_) {
    return false;
  }
}

String? _isoCountry(String? raw) {
  if (raw == null) return null;
  final code = raw.trim().toUpperCase();
  if (code.length != 2) return null;
  final a = code.codeUnitAt(0);
  final b = code.codeUnitAt(1);
  if (a < 65 || a > 90 || b < 65 || b > 90) return null;
  return code;
}

class Session extends ChangeNotifier {
  Session(this.auth) : api = WorkyApi(auth) {
    outbox = MediaQueue(api, onPublished: _published);
  }

  final FirebaseAuth auth;
  final WorkyApi api;
  late final MediaQueue outbox;
  SharedPreferences? _prefs;
  GoogleSignInAccount? _google;

  bool ready = false;
  String? lang;
  Set<String> spoken = {};
  String? whatsapp;
  bool admin = false;
  User? user;
  double? lat;
  double? lng;
  String? country;
  String? countryName;
  double? _flagLat;
  double? _flagLng;
  var _flagGen = 0;
  static const feedTtl = Duration(hours: 1);
  final Map<String, FeedHold> feedCache = {};
  bool feedBypass = false;

  Future<void> boot() async {
    _prefs = await SharedPreferences.getInstance();
    await outbox.attach(_prefs!);
    lang = _prefs!.getString('lang');
    spoken = {
      for (final code in (_prefs!.getString('spoken') ?? '').split(','))
        if (code.isNotEmpty) code,
    };
    whatsapp = _prefs!.getString('whatsapp');
    final cachedLat = _prefs!.getDouble('lat');
    final cachedLng = _prefs!.getDouble('lng');
    if (cachedLat != null && cachedLng != null) {
      lat = cachedLat;
      lng = cachedLng;
    }
    country = _isoCountry(_prefs!.getString('country'));
    countryName = _prefs!.getString('countryName');
    _flagLat = _prefs!.getDouble('flagLat');
    _flagLng = _prefs!.getDouble('flagLng');
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
    unawaited(_resolveCountry());
    if (user != null) outbox.kick();
    auth.authStateChanges().listen((next) async {
      user = next;
      if (next == null) _google = null;
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

  Future<void> setSpoken(Set<String> codes) async {
    spoken = codes;
    final saved = codes.where((code) => code.isNotEmpty).join(',');
    if (saved.isEmpty) {
      await _prefs?.remove('spoken');
    } else {
      await _prefs?.setString('spoken', saved);
    }
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
    if (value.isNotEmpty && !validPhone(value)) {
      throw const FormatException('number');
    }
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
    unawaited(_resolveCountry());
    if (user != null) {
      try {
        await api.saveMe(lang: lang, whatsapp: whatsapp, lat: lat, lng: lng);
      } catch (_) {}
    }
    return true;
  }

  Future<void> _resolveCountry() async {
    if (kIsWeb) return;
    final hereLat = lat;
    final hereLng = lng;
    if (hereLat == null || hereLng == null) return;
    final anchorLat = _flagLat;
    final anchorLng = _flagLng;
    if (anchorLat != null &&
        anchorLng != null &&
        (hereLat - anchorLat).abs() <= 0.1 &&
        (hereLng - anchorLng).abs() <= 0.1) {
      return;
    }
    final gen = ++_flagGen;
    String? iso;
    String? name;
    try {
      final marks = await Geocoding().placemarkFromCoordinates(
        hereLat,
        hereLng,
      );
      if (gen != _flagGen || lat != hereLat || lng != hereLng) return;
      if (marks.isNotEmpty) {
        iso = _isoCountry(marks.first.isoCountryCode);
        final label = marks.first.country?.trim();
        if (iso != null && label != null && label.isNotEmpty) name = label;
      }
    } catch (_) {
      if (gen != _flagGen || lat != hereLat || lng != hereLng) return;
    }
    _flagLat = hereLat;
    _flagLng = hereLng;
    final changed = country != iso || countryName != name;
    country = iso;
    countryName = name;
    final prefs = _prefs;
    if (prefs != null) {
      await prefs.setDouble('flagLat', hereLat);
      await prefs.setDouble('flagLng', hereLng);
      if (iso == null) {
        await prefs.remove('country');
        await prefs.remove('countryName');
      } else {
        await prefs.setString('country', iso);
        if (name == null) {
          await prefs.remove('countryName');
        } else {
          await prefs.setString('countryName', name);
        }
      }
    }
    if (changed) notifyListeners();
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
    _google = account;
    final idToken = account.authentication.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw const GoogleSignInException(
        code: GoogleSignInExceptionCode.unknownError,
        description: 'Google did not return a sign-in token.',
      );
    }
    await auth.signInWithCredential(
      GoogleAuthProvider.credential(idToken: idToken),
    );
  }

  static const _calendarScopes = [
    'https://www.googleapis.com/auth/calendar.events.owned',
  ];

  /// A calendar token for the signed-in Google account.
  ///
  /// [prompt] asks for the calendar permission. Sign-in runs only when no
  /// Google account is already held.
  Future<String?> calendarToken({bool prompt = false}) async {
    if (kIsWeb || kUseEmulator) return null;
    try {
      var account = _google;
      if (account == null) {
        if (!prompt) return null;
        account = await GoogleSignIn.instance
            .attemptLightweightAuthentication();
        if (account != null) _google = account;
      }
      if (account == null) {
        account = await GoogleSignIn.instance.authenticate();
        _google = account;
      }
      final existing = await account.authorizationClient.authorizationForScopes(
        _calendarScopes,
      );
      if (existing != null) return existing.accessToken;
      if (!prompt) return null;
      final granted = await account.authorizationClient.authorizeScopes(
        _calendarScopes,
      );
      return granted.accessToken;
    } catch (_) {
      if (!prompt) return null;
      rethrow;
    }
  }

  Future<void> trySilent() async {
    if (kUseEmulator || kIsWeb || auth.currentUser != null) return;
    final account = await GoogleSignIn.instance
        .attemptLightweightAuthentication();
    if (account != null) _google = account;
    final idToken = account?.authentication.idToken;
    if (idToken == null) return;
    await auth.signInWithCredential(
      GoogleAuthProvider.credential(idToken: idToken),
    );
  }

  bool feedIsFresh(String key, double lat, double lng) {
    final hold = feedCache[key];
    if (hold == null) return false;
    if (DateTime.now().millisecondsSinceEpoch - hold.at >=
        feedTtl.inMilliseconds) {
      return false;
    }
    return !needsRing(hold.page, lat, lng);
  }

  void rememberFeed(String key, FeedPage page) {
    feedCache[key] = FeedHold(page, DateTime.now().millisecondsSinceEpoch);
  }

  List<FeedCategory> visible(String key, double lat, double lng) {
    final hold = feedCache[key];
    if (hold == null) return const [];
    return [
      for (final row in hold.page.categories)
        row.copyWith(
          posts: row.isJob ? nearestPosts(row.posts, lat, lng) : const [],
        ),
    ];
  }

  void _published() {
    dropFeed();
    notifyListeners();
  }

  void dropFeed() {
    feedCache.clear();
    feedBypass = true;
  }

  Future<void> deleteAccount() async {
    await outbox.clear();
    await api.deleteMe();
    dropFeed();
    whatsapp = null;
    admin = false;
    _google = null;
    await _prefs?.remove('whatsapp');
    await _analyticsUser(null);
    if (!kUseEmulator && !kIsWeb) {
      await GoogleSignIn.instance.signOut();
    }
    await auth.signOut();
    notifyListeners();
  }

  Future<void> signOut() async {
    await outbox.clear();
    dropFeed();
    whatsapp = null;
    admin = false;
    _google = null;
    await _prefs?.remove('whatsapp');
    await _analyticsUser(null);
    if (!kUseEmulator && !kIsWeb) {
      await GoogleSignIn.instance.signOut();
    }
    await auth.signOut();
    notifyListeners();
  }

  Future<void> _analyticsUser(String? uid) async {
    try {
      await FirebaseAnalytics.instance.setUserId(id: uid);
    } catch (_) {}
  }

  String cacheKey(String parentId) => '$parentId|$lang';
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
