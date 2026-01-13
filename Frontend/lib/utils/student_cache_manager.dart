import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';

// Model class for student with group information
class StudentWithGroups {
  final String id;
  final String studentId;
  final String studentName;
  final List<String> groupIds;
  final List<String> groupNames;

  StudentWithGroups({
    required this.id,
    required this.studentId,
    required this.studentName,
    this.groupIds = const [],
    this.groupNames = const [],
  });

  factory StudentWithGroups.fromJson(Map<String, dynamic> json) {
    return StudentWithGroups(
      id: json['id'] ?? '',
      studentId: json['student_id'] ?? '',
      studentName: json['student_name'] ?? '',
      groupIds: List<String>.from(json['group_ids'] ?? []),
      groupNames: List<String>.from(json['group_names'] ?? []),
    );
  }

  // Check if student is in a specific group
  bool isInGroup(String groupId) => groupIds.contains(groupId);

  // Convert to simple Student format for compatibility
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'student_id': studentId,
      'student_name': studentName,
      'status': 'Not Submitted',
    };
  }
}

// Smart cache manager for students
class StudentCacheManager {
  static final StudentCacheManager _instance = StudentCacheManager._internal();
  factory StudentCacheManager() => _instance;
  StudentCacheManager._internal();

  // In-memory cache
  final Map<String, List<StudentWithGroups>> _cache = {};
  final Map<String, DateTime> _cacheTimestamps = {};
  final http.Client _httpClient = http.Client();

  static const Duration cacheDuration = Duration(minutes: 5);

  // Prefetch all students with group info (ONE request on app start)
  Future<void> prefetchAllStudents(String adminId) async {
    if (adminId.isEmpty) return;

    final cacheKey = 'all_students_$adminId';

    // Skip if cache is fresh
    if (_isCacheFresh(cacheKey)) {
      return;
    }

    try {
      // Fetch all students (using existing endpoint for now)
      final response = await _httpClient.get(
        Uri.parse('${ApiConfig.getAllStudents}?page=1&limit=500&view=list'),
      );

      if (response.statusCode == 200 && response.body.isNotEmpty) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        if (data.containsKey('students')) {
          final studentsList = data['students'] as List;
          final students = studentsList
              .map((s) => StudentWithGroups.fromJson(s as Map<String, dynamic>))
              .toList();

          // Cache ALL students
          _cache[cacheKey] = students;
          _cacheTimestamps[cacheKey] = DateTime.now();

          // Also cache per-group views (will be populated when groups are fetched)
          // This will be called after groups are loaded
        }
      }
    } catch (e) {
      print('Prefetch failed: $e');
    }
  }

  // Fetch and cache group students (derives from main cache when possible)
  Future<void> prefetchGroupStudents(String groupId, String adminId) async {
    if (groupId.isEmpty) return;

    final cacheKey = 'group_students_$groupId';

    // Skip if cache is fresh
    if (_isCacheFresh(cacheKey)) {
      return;
    }

    try {
      final response = await _httpClient.get(
        Uri.parse('${ApiConfig.getGroupStudents}?group_id=$groupId'),
      );

      if (response.statusCode == 200 && response.body.isNotEmpty) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        if (data.containsKey('students')) {
          final studentsList = data['students'] as List;
          final students = studentsList
              .map((s) => StudentWithGroups.fromJson(s as Map<String, dynamic>))
              .toList();

          // Cache group students
          _cache[cacheKey] = students;
          _cacheTimestamps[cacheKey] = DateTime.now();
        }
      }
    } catch (e) {
      print('Prefetch group students failed: $e');
    }
  }

  // Derive group views from cached data (NO network request!)
  void _cacheGroupViews(List<StudentWithGroups> allStudents, Map<String, String> groupIdToName) {
    final groupMap = <String, List<StudentWithGroups>>{};

    for (var student in allStudents) {
      for (var groupId in student.groupIds) {
        groupMap.putIfAbsent(groupId, () => []).add(student);
      }
    }

    // Cache each group view
    groupMap.forEach((groupId, students) {
      final cacheKey = 'group_students_$groupId';
      _cache[cacheKey] = students;
      _cacheTimestamps[cacheKey] = DateTime.now();
    });
  }

  // Get all students (from cache!)
  List<StudentWithGroups> getAllStudents(String adminId) {
    final cacheKey = 'all_students_$adminId';

    if (_isCacheFresh(cacheKey)) {
      return _cache[cacheKey] ?? [];
    }

    return []; // Will trigger prefetch
  }

  // Get group students (from cache!)
  List<StudentWithGroups> getGroupStudents(String groupId) {
    final cacheKey = 'group_students_$groupId';

    if (_isCacheFresh(cacheKey)) {
      return _cache[cacheKey] ?? [];
    }

    return []; // Will trigger prefetch
  }

  bool _isCacheFresh(String key) {
    final timestamp = _cacheTimestamps[key];
    if (timestamp == null) return false;
    return DateTime.now().difference(timestamp) < cacheDuration;
  }

  // Invalidate cache when group membership changes
  void invalidateCache(String adminId) {
    _cache.clear();
    _cacheTimestamps.clear();
    // Re-fetch in background
    prefetchAllStudents(adminId);
  }

  // Clear specific group cache
  void invalidateGroupCache(String groupId) {
    final cacheKey = 'group_students_$groupId';
    _cache.remove(cacheKey);
    _cacheTimestamps.remove(cacheKey);
  }
  
  // Public access to cache for external updates
  void cacheGroupStudents(String groupId, List<StudentWithGroups> students) {
    final cacheKey = 'group_students_$groupId';
    _cache[cacheKey] = students;
    _cacheTimestamps[cacheKey] = DateTime.now();
  }

  // Check if cache exists and is fresh
  bool hasFreshCache(String adminId) {
    final cacheKey = 'all_students_$adminId';
    return _isCacheFresh(cacheKey);
  }

  // Get cache age
  Duration? getCacheAge(String adminId) {
    final cacheKey = 'all_students_$adminId';
    final timestamp = _cacheTimestamps[cacheKey];
    if (timestamp == null) return null;
    return DateTime.now().difference(timestamp);
  }
}

