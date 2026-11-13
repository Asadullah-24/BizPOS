import 'dart:io';

import 'package:firebase_core/firebase_core.dart';

/// Firebase project "bizpos-7e092". These values are public identifiers
/// (security comes from firebase/firestore.rules), so they can live in source.
/// Leave apiKey empty to run fully offline without accounts.
class FirebaseConfig {
  static const android = FirebaseOptions(
    apiKey: 'AIzaSyB3av-g1V4TiOTN_0u5BW7AJ44p3hF4IyI',
    appId: '1:63118621975:android:e14e56611523aeb2a84b52',
    messagingSenderId: '63118621975',
    projectId: 'bizpos-7e092',
    storageBucket: 'bizpos-7e092.firebasestorage.app',
  );

  static const ios = FirebaseOptions(
    apiKey: 'AIzaSyB4jcYs8nCfsP9YX4aqlozicgtWL5b6ppM',
    appId: '1:63118621975:ios:0bd215726982294ba84b52',
    messagingSenderId: '63118621975',
    projectId: 'bizpos-7e092',
    storageBucket: 'bizpos-7e092.firebasestorage.app',
    iosBundleId: 'com.bizpos.bizpos',
    iosClientId: '63118621975-gd1qkahehp81o2keffmv8sii9jrk6r90.apps.googleusercontent.com',
  );

  /// Web app config, for the future web admin panel and marketplace site.
  static const web = FirebaseOptions(
    apiKey: 'AIzaSyBwC3mZE1eseWzjoUCkHV2e_Q3KAAYvvE8',
    appId: '1:63118621975:web:172defd7f1978470a84b52',
    messagingSenderId: '63118621975',
    projectId: 'bizpos-7e092',
    authDomain: 'bizpos-7e092.firebaseapp.com',
    storageBucket: 'bizpos-7e092.firebasestorage.app',
  );

  /// OAuth "Web client" (client_type 3 in google-services.json). Google
  /// sign-in on Android needs it to get an ID token for Firebase.
  static const webClientId = '63118621975-930926747j8tgnhg3qc67ggratueuf9v.apps.googleusercontent.com';

  static bool get configured => (Platform.isIOS ? ios : android).apiKey.isNotEmpty;

  static FirebaseOptions get current => Platform.isIOS ? ios : android;
}
