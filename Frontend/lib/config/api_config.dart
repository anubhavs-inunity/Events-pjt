class ApiConfig {
  // For web/Chrome: use localhost:8080
  // For Android emulator: use http://10.0.2.2:8080
  // For physical device: use http://YOUR_COMPUTER_IP:8080
static const String baseUrl = 'http://192.168.0.166:8080';
  
  // API endpoints
  static String get adminLogin => '$baseUrl/api/admin-login';
  static String get studentLogin => '$baseUrl/api/student-login';
  static String get setCenter => '$baseUrl/api/set-center';
  static String get startWindow => '$baseUrl/api/start-window';
  static String get closeWindow => '$baseUrl/api/close-window';
  static String get submitAttendance => '$baseUrl/api/submit-attendance';
  static String get downloadCsv => '$baseUrl/api/download-csv';
  static String get getAdminLocation => '$baseUrl/api/get-admin-location';
  static String get getWindowStatus => '$baseUrl/api/get-window-status';
  static String get getAllStudentLocations => '$baseUrl/api/get-all-student-locations';
  static String get getAllStudents => '$baseUrl/api/get-all-students';
  
  // Group management endpoints
  static String get createGroup => '$baseUrl/api/create-group';
  static String get getMyGroups => '$baseUrl/api/get-my-groups';
  static String get addStudentsToGroup => '$baseUrl/api/add-students-to-group';
  static String get getGroupStudents => '$baseUrl/api/get-group-students';
  static String get deleteGroup => '$baseUrl/api/delete-group';
  
  // Student management endpoints
  static String get addStudent => '$baseUrl/api/add-student';
  static String getStudentAttendanceHistory(String studentId) => '$baseUrl/api/get-student-attendance-history?student_id=$studentId';
  
  // FCM endpoints
  static String get saveFcmToken => '$baseUrl/api/save-fcm-token';
  
  // Messaging endpoints
  static String get sendBroadcastMessage => '$baseUrl/api/send-broadcast-message';
  static String getMessages(String studentId) => '$baseUrl/api/get-messages?student_id=$studentId';
  static String get markMessageRead => '$baseUrl/api/mark-message-read';
  static String get deleteMessage => '$baseUrl/api/delete-message';
  
  // Session management endpoints
  static String get updateSessionName => '$baseUrl/api/update-session-name';
}

