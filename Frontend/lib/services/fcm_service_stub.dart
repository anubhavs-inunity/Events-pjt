// Stub implementation for web platform
// This file is used when compiling for web to avoid Firebase Messaging imports

class FCMService {
  static final FCMService _instance = FCMService._internal();
  factory FCMService() => _instance;
  FCMService._internal();

  String? _fcmToken;
  String? _userId;
  String? _userType;

  Function(dynamic)? onMessageReceived;
  Function(dynamic)? onNotificationTapped;

  // Initialize Firebase (stub for web)
  Future<void> initializeFirebase() async {
    print('ℹ️ FCM is not supported on web platform');
  }

  // Initialize FCM (stub for web)
  Future<void> initialize() async {
    print('ℹ️ FCM is not supported on web platform');
  }

  // Set user info (stub for web)
  Future<void> setUserInfo(String userId, String userType) async {
    _userId = userId;
    _userType = userType;
  }

  // Clear user info (stub for web)
  Future<void> clearUserInfo() async {
    _userId = null;
    _userType = null;
  }

  String? getToken() => null;

  Future<void> subscribeToTopic(String topic) async {
    // No-op on web
  }

  Future<void> unsubscribeFromTopic(String topic) async {
    // No-op on web
  }

  Future<void> deleteToken() async {
    // No-op on web
  }
}

