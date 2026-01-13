import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../config/api_config.dart';

// Conditional imports - only import Firebase on non-web platforms
import 'package:firebase_core/firebase_core.dart' 
    if (dart.library.html) '../firebase_core_stub.dart';
import 'package:firebase_messaging/firebase_messaging.dart' 
    if (dart.library.html) '../firebase_messaging_stub.dart';
import '../firebase_options.dart' 
    if (dart.library.html) '../firebase_options_stub.dart';

// Background message handler (must be top-level)
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Import Firebase conditionally
  try {
    // Check if Firebase is already initialized
    try {
      Firebase.app();
    } catch (e) {
      // Not initialized, initialize it
      try {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      } catch (e2) {
        // If options are not available (web), try without options
        await Firebase.initializeApp();
      }
    }
    print('📬 Background message: ${message.messageId}');
    print('📬 Message data: ${message.data}');
  } catch (e) {
    print('Error in background handler: $e');
  }
}

class FCMService {
  static final FCMService _instance = FCMService._internal();
  factory FCMService() => _instance;
  FCMService._internal();

  // Lazy-load FirebaseMessaging to avoid accessing it before Firebase is initialized
  FirebaseMessaging? _firebaseMessaging;
  FirebaseMessaging get _messaging {
    _firebaseMessaging ??= FirebaseMessaging.instance;
    return _firebaseMessaging!;
  }
  
  final FlutterLocalNotificationsPlugin _localNotifications = 
      FlutterLocalNotificationsPlugin();
  
  String? _fcmToken;
  String? _userId;
  String? _userType; // "admin" or "student"
  
  Function(dynamic)? onMessageReceived;
  Function(dynamic)? onNotificationTapped;

  // Initialize Firebase (called from main.dart)
  Future<void> initializeFirebase() async {
    try {
      // Check if Firebase is already initialized
      try {
        Firebase.app();
        print('✅ Firebase already initialized');
        return;
      } catch (e) {
        // Not initialized yet, continue
        print('ℹ️ Firebase not initialized yet, initializing...');
      }
      
      // Initialize Firebase with platform-specific options
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      
      // Verify initialization
      final app = Firebase.app();
      print('✅ Firebase initialized successfully: ${app.name}');
      
      // Register background handler
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      print('✅ Background message handler registered');
    } catch (e, stackTrace) {
      print('❌ Error initializing Firebase: $e');
      print('❌ Stack trace: $stackTrace');
      rethrow; // Re-throw to let main.dart handle it
    }
  }

  // Initialize FCM
  Future<void> initialize() async {
    try {
      // Verify Firebase is initialized
      try {
        Firebase.app();
      } catch (e) {
        print('❌ Firebase not initialized, cannot initialize FCM');
        throw Exception('Firebase must be initialized before FCM');
      }
      
      // Request permissions
      NotificationSettings settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        print('✅ User granted notification permission');
      } else if (settings.authorizationStatus == AuthorizationStatus.provisional) {
        print('⚠️ User granted provisional notification permission');
      } else {
        print('❌ User declined notification permission');
        return;
      }

      // Initialize local notifications for foreground messages
      await _initializeLocalNotifications();

      // Get FCM token
      _fcmToken = await _messaging.getToken();
      print('📱 FCM Token: $_fcmToken');
      
      // Save token to backend if user is logged in
      if (_fcmToken != null && _userId != null) {
        await _saveTokenToBackend(_fcmToken!, _userId!, _userType ?? 'student');
      }

      // Listen for token refresh
      _messaging.onTokenRefresh.listen((newToken) {
        print('🔄 FCM Token refreshed: $newToken');
        _fcmToken = newToken;
        if (_userId != null) {
          _saveTokenToBackend(newToken, _userId!, _userType ?? 'student');
        }
      });

      // Handle foreground messages
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

      // Handle notification taps (when app is in background)
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        print('🔔 Notification tapped: ${message.messageId}');
        // Check if it's a broadcast message
        if (message.data!= null && message.data!['type'] == 'broadcast_message') {
          // Navigate to messages page if student
          // This will be handled by the app's navigation
        }
        onNotificationTapped?.call(message);
      });

      // Check if app was opened from notification (when app was terminated)
      RemoteMessage? initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) {
        print('🔔 App opened from notification: ${initialMessage.messageId}');
        onNotificationTapped?.call(initialMessage);
      }
    } catch (e) {
      print('❌ Error initializing FCM: $e');
    }
  }

  Future<void> _initializeLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        // Handle notification tap
        if (response.payload != null) {
          try {
            final data = jsonDecode(response.payload!);
            // You can navigate to specific screens based on data
            print('📬 Notification tapped with payload: $data');
            onNotificationTapped?.call(null); // Trigger callback
          } catch (e) {
            print('Error parsing notification payload: $e');
          }
        }
      },
    );

    // Create notification channel for Android with high importance
    const androidChannel = AndroidNotificationChannel(
      'attendance_channel',
      'Attendance Notifications',
      description: 'Notifications for attendance system events',
      importance: Importance.max, // Changed to max for better visibility
      playSound: true,
      enableVibration: true,
      showBadge: true,
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);
    
    print('✅ Local notifications initialized');
  }

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    print('📨 Foreground message received: ${message.messageId}');
    print('📨 Message data: ${message.data}');
    print('📨 Notification title: ${message.notification?.title}');
    print('📨 Notification body: ${message.notification?.body}');
    
    // Always show local notification (even in foreground)
    // This ensures users see it in notification tray
    RemoteNotification? notification = message.notification;
    String title = notification?.title ?? 
                  (message.data != null ? message.data!['title'] : null) ?? 
                  'New Message';
    String body = notification?.body ?? 
                 (message.data != null ? message.data!['message'] : null) ?? 
                 '';

    if (title.isNotEmpty || body.isNotEmpty) {
      // Use a unique ID based on message ID or timestamp
      int notificationId = message.messageId?.hashCode ?? 
                          DateTime.now().millisecondsSinceEpoch ~/ 1000;
      
      await _localNotifications.show(
        notificationId,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            'attendance_channel',
            'Attendance Notifications',
            channelDescription: 'Notifications for attendance system',
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
            playSound: true,
            enableVibration: true,
            showWhen: true,
            enableLights: true,
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        payload: jsonEncode(message.data),
      );
      print('✅ Local notification shown: $title - $body');
    }

    // Call callback (this triggers the popup)
    // The popup and notification will both show
    onMessageReceived?.call(message);
  }

  Future<void> _saveTokenToBackend(String token, String userId, String userType) async {
    try {
      // Save token locally
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('fcm_token', token);
      await prefs.setString('fcm_user_id', userId);
      await prefs.setString('fcm_user_type', userType);

      // Send token to your backend
      try {
        final response = await http.post(
          Uri.parse(ApiConfig.saveFcmToken),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'fcm_token': token,
            'user_id': userId,
            'user_type': userType,
            'device_type': 'mobile',
          }),
        );

        if (response.statusCode == 200) {
          print('✅ FCM token saved to backend');
        } else {
          print('⚠️ Failed to save FCM token: ${response.statusCode}');
          if (response.body.isNotEmpty) {
            try {
              final error = jsonDecode(response.body);
              print('Error details: $error');
            } catch (e) {
              // Ignore parse errors
            }
          }
        }
      } catch (e) {
        print('❌ Error saving FCM token: $e');
        // Don't throw - token saving is not critical
      }
    } catch (e) {
      print('❌ Error saving FCM token: $e');
      // Don't throw - token saving is not critical for app functionality
    }
  }

  // Set user info after login
  Future<void> setUserInfo(String userId, String userType) async {
    _userId = userId;
    _userType = userType;
    
    // Save token if we have it
    if (_fcmToken != null) {
      await _saveTokenToBackend(_fcmToken!, userId, userType);
    }
  }

  // Clear user info on logout
  Future<void> clearUserInfo() async {
    _userId = null;
    _userType = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('fcm_user_id');
    await prefs.remove('fcm_user_type');
  }

  String? getToken() => _fcmToken;

  Future<void> subscribeToTopic(String topic) async {
    try {
      await _messaging.subscribeToTopic(topic);
      print('✅ Subscribed to topic: $topic');
    } catch (e) {
      print('❌ Error subscribing to topic: $e');
    }
  }

  Future<void> unsubscribeFromTopic(String topic) async {
    try {
      await _messaging.unsubscribeFromTopic(topic);
      print('✅ Unsubscribed from topic: $topic');
    } catch (e) {
      print('❌ Error unsubscribing from topic: $e');
    }
  }

  // Delete token (for logout)
  Future<void> deleteToken() async {
    try {
      await _messaging.deleteToken();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('fcm_token');
      _fcmToken = null;
      print('✅ FCM token deleted');
    } catch (e) {
      print('❌ Error deleting FCM token: $e');
    }
  }
}

