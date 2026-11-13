import 'dart:io';

import 'package:firebase_core/firebase_core.dart';

/// Firebase project settings. These values are public identifiers (security
/// comes from firebase/firestore.rules), so they can live in the source.
/// Fill them from Firebase console > Project settings > Your apps.
/// While they are empty the app runs fully offline without accounts.
class FirebaseConfig {
  static const android = FirebaseOptions(
    apiKey: '',
    appId: '',
    messagingSenderId: '',
    projectId: '',
    storageBucket: '',
  );

  static const ios = FirebaseOptions(
    apiKey: '',
    appId: '',
    messagingSenderId: '',
    projectId: '',
    storageBucket: '',
    iosBundleId: 'com.bizpos.bizpos',
    iosClientId: '',
  );

  /// OAuth "Web client" id (Authentication > Sign-in method > Google > Web SDK
  /// configuration). Needed for Google sign-in on Android.
  static const webClientId = '';

  static bool get configured => (Platform.isIOS ? ios : android).apiKey.isNotEmpty;

  static FirebaseOptions get current => Platform.isIOS ? ios : android;
}
