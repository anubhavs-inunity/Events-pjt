// Stub for firebase_messaging on web
class FirebaseMessaging {
  static FirebaseMessaging get instance => FirebaseMessaging();
  
  // Static streams (like the real API)
  static Stream<RemoteMessage> get onMessage => const Stream.empty();
  static Stream<RemoteMessage> get onMessageOpenedApp => const Stream.empty();
  static void onBackgroundMessage(Future<void> Function(RemoteMessage) handler) {}
  
  // Instance methods
  Future<NotificationSettings> requestPermission({required bool alert, required bool badge, required bool sound, required bool provisional}) async {
    return NotificationSettings(authorizationStatus: AuthorizationStatus.denied);
  }
  Future<String?> getToken() async => null;
  Stream<String> get onTokenRefresh => const Stream.empty();
  Future<RemoteMessage?> getInitialMessage() async => null;
  Future<void> subscribeToTopic(String topic) async {}
  Future<void> unsubscribeFromTopic(String topic) async {}
  Future<void> deleteToken() async {}
}

class RemoteMessage {
  final String? messageId;
  final Map<String, dynamic>? data;
  final RemoteNotification? notification;
  RemoteMessage({this.messageId, this.data, this.notification});
}

class RemoteNotification {
  final String? title;
  final String? body;
  final AndroidNotification? android;
  RemoteNotification({this.title, this.body, this.android});
}

class AndroidNotification {
  final String? smallIcon;
  AndroidNotification({this.smallIcon});
}

class NotificationSettings {
  final AuthorizationStatus authorizationStatus;
  NotificationSettings({required this.authorizationStatus});
}

enum AuthorizationStatus {
  authorized,
  denied,
  notDetermined,
  provisional,
}

