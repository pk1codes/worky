import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    if (defaultTargetPlatform == TargetPlatform.android) return android;
    return web;
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyAVt4QMe6Ci3xJ3joRx36If5wibYw89_To',
    appId: '1:69334014512:web:7e3670c777adb32a766bf5',
    messagingSenderId: '69334014512',
    projectId: 'worky-93fbc',
    authDomain: 'worky-93fbc.firebaseapp.com',
    storageBucket: 'worky-93fbc.firebasestorage.app',
    measurementId: 'G-CN23BLH6VP',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyADMOPKBm89MTfbPLG3zirL6U-l_-KYHKc',
    appId: '1:69334014512:android:825df7f3d703dda6766bf5',
    messagingSenderId: '69334014512',
    projectId: 'worky-93fbc',
    storageBucket: 'worky-93fbc.firebasestorage.app',
  );
}
