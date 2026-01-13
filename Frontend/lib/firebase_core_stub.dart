// Stub for firebase_core on web
class Firebase {
  static Future<void> initializeApp({dynamic options}) async {
    // No-op on web
  }
  
  static dynamic app([String name = '[DEFAULT]']) {
    throw UnsupportedError('Firebase is not supported on web');
  }
}

class FirebaseApp {
  final String name;
  FirebaseApp(this.name);
}

