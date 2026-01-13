import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:circular_countdown_timer/circular_countdown_timer.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import '../config/api_config.dart';
import '../widgets/custom_loader.dart';
import '../widgets/student_card.dart';
import '../models/student.dart';
import '../utils/coordinate_formatter.dart';
import '../utils/student_cache_manager.dart';
import 'unified_login_page.dart';
import 'view_student_locations_page.dart';
import 'fullscreen_map_page.dart';
import 'broadcast_message_page.dart';
import 'add_student_page.dart';
import 'package:path_provider/path_provider.dart';

class AdminDashboardPage extends StatefulWidget {
  final String? adminId;
  final String? adminUsername;
  
  const AdminDashboardPage({super.key, this.adminId, this.adminUsername});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  // State variables
  Position? _adminLocation;
  bool _attendanceActive = false;
  int _remainingSeconds = 600; // 10 minutes = 600 seconds
  String _sessionName = 'Workshop_Day2';
  double _thresholdMeters = 100.0;
  Timer? _countdownTimer;
  bool _isRecordingLocation = false;
  bool _isStartingWindow = false;
  bool _isDownloading = false;

  Timer? _statusPollTimer;
  CountDownController _countDownController = CountDownController();
  DateTime? _windowStartTime;
  DateTime? _windowEndTime;
  final MapController _mapController = MapController();
  bool _isMapHovered = false;
  
  // Sidebar state
  int _selectedIndex = 0;
  List<Student>? _allStudents;
  bool _isLoadingStudents = false;
  int _currentPage = 1;
  int _totalPages = 1;
  bool _hasMore = false;
  final ScrollController _studentsScrollController = ScrollController();
  Timer? _scrollDebounce;
  
  // HTTP client for connection pooling
  final http.Client _httpClient = http.Client();
  
  // Group management state
  String? _currentGroupId;
  String? _currentGroupName;
  List<Map<String, dynamic>>? _myGroups;
  bool _isLoadingGroups = false;
  
  // Frontend cache for groups (Phase 1 optimization)
  List<Map<String, dynamic>>? _cachedGroups;
  DateTime? _lastGroupsFetchTime;
  static const _groupsCacheDuration = Duration(minutes: 5);
  
  // Frontend cache for students (for fast loading)
  List<Student>? _cachedStudents;
  DateTime? _lastStudentsFetchTime;
  static const _studentsCacheDuration = Duration(minutes: 5);
  
  // Smart student cache manager (Ultra-optimized)
  final StudentCacheManager _studentCache = StudentCacheManager();
  
  // Attendance scope: true = group only, false = all students
  bool _attendanceScopeGroupOnly = true;

  @override
  void initState() {
    super.initState();
    // Restore saved state first
    _restoreState();
    // Fetch admin location and window status from backend on load
    _fetchAdminLocation();
    _fetchWindowStatus();
    // Load groups if admin ID is available (force fetch on initial load)
    if (widget.adminId != null) {
      _fetchMyGroups(forceRefresh: true).then((_) {
        // After groups are loaded, restore selected group
        _restoreSelectedGroup();
      });
      
      // Prefetch all students in background (ONE request for entire session!)
      _studentCache.prefetchAllStudents(widget.adminId!);
    }
    // ❌ Removed: Pre-fetch students on page load (lazy loading - only fetch when needed)
    // ✅ Students will be fetched when user opens "View All Students" or "Create Group" dialogs
    // Poll every 2 seconds to keep timer in sync with backend
    _statusPollTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (mounted) {
        _fetchWindowStatus();
      } else {
        timer.cancel();
      }
    });
  }

  // Save state to SharedPreferences
  Future<void> _saveState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_currentGroupId != null) {
        await prefs.setString('admin_current_group_id', _currentGroupId!);
      }
      if (_currentGroupName != null) {
        await prefs.setString('admin_current_group_name', _currentGroupName!);
      }
      await prefs.setString('admin_session_name', _sessionName);
      await prefs.setBool('admin_attendance_active', _attendanceActive);
      await prefs.setInt('admin_remaining_seconds', _remainingSeconds);
      debugPrint('✅ State saved: group=$_currentGroupId, session=$_sessionName, active=$_attendanceActive');
    } catch (e) {
      debugPrint('❌ Error saving state: $e');
    }
  }

  // Restore state from SharedPreferences
  Future<void> _restoreState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedGroupId = prefs.getString('admin_current_group_id');
      final savedGroupName = prefs.getString('admin_current_group_name');
      final savedSessionName = prefs.getString('admin_session_name');
      
      if (mounted) {
        setState(() {
          if (savedGroupId != null) {
            _currentGroupId = savedGroupId;
          }
          if (savedGroupName != null) {
            _currentGroupName = savedGroupName;
          }
          if (savedSessionName != null && savedSessionName.isNotEmpty) {
            _sessionName = savedSessionName;
          }
        });
        debugPrint('✅ State restored: group=$_currentGroupId, session=$_sessionName');
      }
    } catch (e) {
      debugPrint('❌ Error restoring state: $e');
    }
  }

  // Restore selected group after groups are loaded
  void _restoreSelectedGroup() {
    if (_currentGroupId != null && _myGroups != null) {
      final group = _myGroups!.firstWhere(
        (g) => g['id'] == _currentGroupId,
        orElse: () => {},
      );
      if (group.isNotEmpty && mounted) {
        setState(() {
          _currentGroupName = group['name'] as String? ?? _currentGroupName;
        });
        debugPrint('✅ Selected group restored: $_currentGroupName');
      } else {
        // Group not found, clear selection
        if (mounted) {
          setState(() {
            _currentGroupId = null;
            _currentGroupName = null;
          });
          _saveState();
        }
      }
    }
  }

  Future<void> _fetchAdminLocation() async {
    try {
      // Build URL with group_id if available
      String url = ApiConfig.getAdminLocation;
      if (_currentGroupId != null) {
        url = '$url?group_id=$_currentGroupId';
      }
      
      final response = await http.get(Uri.parse(url));
      
      if (response.statusCode == 200 && response.body.isNotEmpty) {
        final data = json.decode(response.body);
        if (mounted) {
          final lat = (data['lat'] as num).toDouble();
          final lon = (data['lon'] as num).toDouble();
          
          if (lat != 0 && lon != 0) {
            setState(() {
              _adminLocation = Position(
                latitude: lat,
                longitude: lon,
                timestamp: DateTime.now(),
                accuracy: 0,
                altitude: 0,
                altitudeAccuracy: 0,
                heading: 0,
                headingAccuracy: 0,
                speed: 0,
                speedAccuracy: 0,
              );
              // Also update threshold if provided
              if (data['threshold'] != null) {
                _thresholdMeters = (data['threshold'] as num).toDouble();
              }
            });
          }
        }
      }
    } catch (e) {
      print('Error fetching admin location: $e');
      // Silent fail
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _statusPollTimer?.cancel();
    _scrollDebounce?.cancel();
    _studentsScrollController.removeListener(_onScroll);
    _studentsScrollController.dispose();
    _httpClient.close(); // Close HTTP client
    // Pause countdown controller before disposing
    try {
      _countDownController.pause();
    } catch (e) {
      // Ignore errors if already disposed
    }
    super.dispose();
  }

  Future<void> _fetchWindowStatus() async {
    try {
      // Build URL with group_id if available
      String url = ApiConfig.getWindowStatus;
      if (_currentGroupId != null) {
        url = '$url?group_id=$_currentGroupId';
      }
      
      final response = await http.get(Uri.parse(url));
      
      if (response.statusCode == 200 && response.body.isNotEmpty) {
        final data = json.decode(response.body);
        if (mounted) {
          final wasActive = _attendanceActive;
          final newActive = data['active'] ?? false;
          final newRemainingSeconds = data['remaining_seconds'] ?? 0;
          
          setState(() {
            _attendanceActive = newActive;
            _remainingSeconds = newRemainingSeconds > 0 ? newRemainingSeconds : 600;
            
            // If window is active, sync the circular countdown timer
            if (_attendanceActive && _remainingSeconds > 0) {
              _countdownTimer?.cancel();
              // Restart the circular countdown timer with new duration
              try {
                _countDownController.restart(duration: _remainingSeconds);
                // Start the timer if window just became active
                if (!wasActive) {
                  Future.delayed(const Duration(milliseconds: 200), () {
                    if (mounted && _attendanceActive) {
                      try {
                        _countDownController.start();
                        debugPrint('Timer started with ${_remainingSeconds} seconds');
                      } catch (e) {
                        debugPrint('Error starting countdown: $e');
                      }
                    }
                  });
                }
              } catch (e) {
                // Ignore if controller is already disposed
                debugPrint('Error restarting countdown: $e');
              }
              // Calculate window times
              _windowEndTime = DateTime.now().add(Duration(seconds: _remainingSeconds));
              if (_windowStartTime == null) {
                _windowStartTime = DateTime.now().subtract(Duration(seconds: 600 - _remainingSeconds));
              }
            } else if (!_attendanceActive) {
              _countdownTimer?.cancel();
              try {
                _countDownController.pause();
              } catch (e) {
                // Ignore if controller is already disposed
              }
              _windowStartTime = null;
              _windowEndTime = null;
            }
          });
        }
      }
    } catch (e) {
      print('Error fetching window status: $e');
      // Silent fail - keep existing state
    }
  }

  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  Future<void> _requestLocationPermission() async {
    final status = await Permission.location.request();
    if (status != PermissionStatus.granted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location permission is required'),
            backgroundColor: Color(0xFFF44336),
          ),
        );
      }
      return;
    }
  }

  Future<void> _recordLocation() async {
    setState(() {
      _isRecordingLocation = true;
    });

    try {
      // Request permission
      await _requestLocationPermission();

      // Get current location
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      // Send to backend
      final body = <String, String>{
        'lat': position.latitude.toString(),
        'lon': position.longitude.toString(),
        'session_name': _sessionName,
        'threshold': _thresholdMeters.toStringAsFixed(0),
      };
      
      // Add group_id if group is selected
      if (_currentGroupId != null) {
        body['group_id'] = _currentGroupId!;
      }
      
      final response = await http.post(
        Uri.parse(ApiConfig.setCenter),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: body,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          setState(() {
            _adminLocation = position;
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Location recorded!\nLat: ${position.latitude.toStringAsFixed(6)}\nLon: ${position.longitude.toStringAsFixed(6)}',
                ),
                backgroundColor: const Color(0xFF4CAF50),
                duration: const Duration(seconds: 3),
              ),
            );
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to record location'),
              backgroundColor: Color(0xFFF44336),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: const Color(0xFFF44336),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRecordingLocation = false;
        });
      }
    }
  }

  Future<void> _startWindow() async {
    if (_adminLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please record location first'),
          backgroundColor: Color(0xFFF44336),
        ),
      );
      return;
    }

    setState(() {
      _isStartingWindow = true;
    });

    try {
      // Build request body with group_id and scope
      final body = <String, String>{
        'lat': _adminLocation!.latitude.toString(),
        'lon': _adminLocation!.longitude.toString(),
        'session_name': _sessionName,
        'threshold': _thresholdMeters.toString(),
      };
      
      // Add group_id if group is selected
      if (_currentGroupId != null) {
        body['group_id'] = _currentGroupId!;
        body['group_only'] = _attendanceScopeGroupOnly ? 'true' : 'false';
      }
      
      final response = await http.post(
        Uri.parse(ApiConfig.startWindow),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: body,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          // Set window start time and immediately show timer
          setState(() {
            _windowStartTime = DateTime.now();
            _windowEndTime = DateTime.now().add(const Duration(minutes: 10));
            _attendanceActive = true; // Set immediately so timer shows
            _remainingSeconds = 600; // Initialize to 10 minutes
          });
          // Start the timer immediately
          try {
            _countDownController.restart(duration: 600);
            Future.delayed(const Duration(milliseconds: 200), () {
              if (mounted && _attendanceActive) {
                try {
                  _countDownController.start();
                  debugPrint('Timer started immediately after window opened');
                } catch (e) {
                  debugPrint('Error starting countdown: $e');
                }
              }
            });
          } catch (e) {
            debugPrint('Error initializing countdown: $e');
          }
          // Fetch updated status from backend (which has the actual timer)
          await _fetchWindowStatus();
          
          // Save state after starting window
          _saveState();

          if (mounted) {
            HapticFeedback.mediumImpact();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Attendance window opened!'),
                backgroundColor: Colors.green[600],
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: const Color(0xFFF44336),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isStartingWindow = false;
        });
      }
    }
  }

  Future<void> _closeWindow() async {
    try {
      // Build request body with group_id if available
      final body = <String, String>{};
      if (_currentGroupId != null) {
        body['group_id'] = _currentGroupId!;
      }
      
      await http.post(
        Uri.parse(ApiConfig.closeWindow),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: body,
      );

      if (mounted) {
        // Fetch updated status from backend
        _fetchWindowStatus();
        
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Attendance Window Closed'),
            content: const Text('The 10-minute attendance window has been closed.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      // Silent fail - window already closed by timer
    }
  }

  Future<void> _downloadCSV() async {
    setState(() {
      _isDownloading = true;
    });

    try {
      // Build URL with group_id if available
      String url = ApiConfig.downloadCsv;
      if (_currentGroupId != null) {
        url = '$url?group_id=$_currentGroupId';
      }
      
      final response = await http.get(
        Uri.parse(url),
      );

      if (response.statusCode == 200) {
        // Get CSV content
        final csvContent = response.body;
        
        // Create filename with timestamp
        final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.')[0];
        final filename = '${_sessionName}_$timestamp.csv';

        // Save to device storage (Downloads if available, else app documents)
        if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
          try {
            Directory? targetDir;
            if (Platform.isAndroid) {
              final dirs = await getExternalStorageDirectories(type: StorageDirectory.downloads);
              if (dirs != null && dirs.isNotEmpty) {
                targetDir = dirs.first;
              }
            }
            targetDir ??= await getApplicationDocumentsDirectory();

            final filePath = '${targetDir.path}/$filename';
            final file = File(filePath);
            await file.writeAsString(csvContent);

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('CSV saved to $filePath'),
                  backgroundColor: const Color(0xFF4CAF50),
                  duration: const Duration(seconds: 4),
                ),
              );
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Saved CSV content to clipboard view (file write failed: $e)'),
                  backgroundColor: const Color(0xFFF44336),
                  duration: const Duration(seconds: 5),
                ),
              );
            }
          }
        } else {
          // Web / desktop fallback: show dialog for copy
          if (mounted) {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('CSV Data Downloaded'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'File: $filename',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'CSV Content (tap to copy):',
                        style: TextStyle(fontSize: 12, color: Color(0xFF757575)),
                      ),
                      const SizedBox(height: 8),
                      SelectableText(
                        csvContent,
                        style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ],
              ),
            );
          }
        }
      } else {
        final data = json.decode(response.body);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(data['error'] ?? 'Failed to download CSV'),
              backgroundColor: const Color(0xFFF44336),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: const Color(0xFFF44336),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDownloading = false;
        });
      }
    }
  }

  void _handleLogout() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (context) => const UnifiedLoginPage(),
      ),
      (route) => false,
    );
  }

  Future<void> _fetchAllStudents({bool loadMore = false, bool forceRefresh = false}) async {
    if (_isLoadingStudents && !forceRefresh) return; // Prevent concurrent requests (unless forcing refresh)
    
    // Phase 1 Optimization: Check frontend cache first (0ms load time!)
    if (!forceRefresh && 
        !loadMore &&
        _cachedStudents != null && 
        _cachedStudents!.isNotEmpty &&
        _lastStudentsFetchTime != null &&
        DateTime.now().difference(_lastStudentsFetchTime!) < _studentsCacheDuration) {
      // Cache is fresh - use it immediately (no network call = 0ms, 0 battery!)
      debugPrint('DEBUG: _fetchAllStudents - Using cached data (no network call)');
      if (mounted) {
        setState(() {
          _allStudents = List<Student>.from(_cachedStudents!);
          _isLoadingStudents = false;
        });
      }
      return; // ✅ No network call!
    }
    
    // Show cached data immediately if available (optimistic UI)
    if (_cachedStudents != null && _cachedStudents!.isNotEmpty && !loadMore && mounted) {
      setState(() {
        _allStudents = List<Student>.from(_cachedStudents!);
      });
    }
    
    // Show loading only if cache is empty
    if (_cachedStudents == null || _cachedStudents!.isEmpty || loadMore) {
      if (mounted) {
        setState(() {
          _isLoadingStudents = true;
        });
      }
    }

    try {
      final page = loadMore ? _currentPage + 1 : 1;
      // Use smaller initial page size for faster loading (20 students per page)
      final limit = loadMore ? 20 : 20;
      // Add cache_bust parameter if forceRefresh is true to ensure fresh data
      final cacheBust = forceRefresh ? '&_t=${DateTime.now().millisecondsSinceEpoch}' : '';
      final url = Uri.parse('${ApiConfig.getAllStudents}?page=$page&limit=$limit&view=list$cacheBust');
      final response = await _httpClient.get(url);
      
      if (response.statusCode == 200 && response.body.isNotEmpty) {
        // Parse JSON efficiently
        final data = json.decode(response.body) as Map<String, dynamic>;
        
        if (mounted && data.containsKey('students')) {
          final studentsList = data['students'] as List;
          if (studentsList.isNotEmpty) {
            // Parse to Student model objects efficiently
            final newStudents = studentsList
                .cast<Map<String, dynamic>>()
                .map((json) => Student.fromJson(json))
                .toList();
            
            if (mounted) {
              setState(() {
                if (loadMore && _allStudents != null) {
                  _allStudents!.addAll(newStudents);
                } else {
                  _allStudents = newStudents;
                  // Cache the first page for instant loading next time
                  _cachedStudents = List<Student>.from(newStudents);
                  _lastStudentsFetchTime = DateTime.now();
                }
                _currentPage = data['page'] as int? ?? page;
                _totalPages = data['totalPages'] as int? ?? 1;
                _hasMore = data['hasMore'] as bool? ?? false;
                _isLoadingStudents = false;
              });
            }
          } else {
            if (mounted) {
              setState(() {
                if (!loadMore) {
                  _allStudents = [];
                }
                _isLoadingStudents = false;
              });
            }
          }
        } else {
          if (mounted) {
            setState(() {
              if (!loadMore) {
                _allStudents = [];
              }
              _isLoadingStudents = false;
            });
          }
        }
      } else {
        if (mounted && !loadMore) {
          setState(() {
            _allStudents = [];
            _isLoadingStudents = false;
          });
        }
      }
    } catch (e) {
      debugPrint('Error fetching students: $e');
      if (mounted && !loadMore) {
        setState(() {
          _allStudents = [];
          _isLoadingStudents = false;
        });
      }
    }
  }

  void _loadMoreStudents() {
    if (_hasMore && !_isLoadingStudents) {
      _fetchAllStudents(loadMore: true);
    }
  }

  // Debounced scroll listener for better performance
  void _onScroll() {
    if (_scrollDebounce?.isActive ?? false) {
      _scrollDebounce!.cancel();
    }
    
    _scrollDebounce = Timer(const Duration(milliseconds: 200), () {
      if (_isLoadingStudents || !_hasMore) return;
      
      final scrollPosition = _studentsScrollController.position;
      if (scrollPosition.pixels >= scrollPosition.maxScrollExtent * 0.8) {
        _loadMoreStudents();
      }
    });
  }

  Widget _buildActionButtonsGrid() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Quick Actions',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey[800],
            ),
          ),
          const SizedBox(height: 16),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 2.2,
            children: [
              _buildActionGridButton(
                icon: Icons.group_add,
                label: 'Create Group',
                color: const Color(0xFFE57373),
                onTap: () => _showCreateGroupDialog(),
              ),
              _buildActionGridButton(
                icon: Icons.folder,
                label: 'My Groups',
                color: const Color(0xFFBA68C8),
                onTap: () => _showMyGroupsDialog(),
              ),
              _buildActionGridButton(
                icon: Icons.group,
                label: 'View Group Students',
                color: const Color(0xFF64B5F6),
                onTap: () {
                  if (_currentGroupId != null) {
                    _showGroupStudentsDialog(_currentGroupId!, _currentGroupName ?? 'Group');
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Please select a group first'),
                        backgroundColor: Colors.orange,
                      ),
                    );
                  }
                },
              ),
              _buildActionGridButton(
                icon: Icons.people,
                label: 'View All Students',
                color: const Color(0xFF81C784),
                onTap: () => _showAllStudentsDialog(),
              ),
              _buildActionGridButton(
                icon: Icons.location_on,
                label: 'Student Locations',
                color: const Color(0xFFFFB74D),
                onTap: () {
                  if (_adminLocation != null) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ViewStudentLocationsPage(
                          adminLocation: LatLng(
                            _adminLocation!.latitude,
                            _adminLocation!.longitude,
                          ),
                          thresholdMeters: _thresholdMeters,
                        ),
                      ),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Please record your location first'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                },
              ),
              _buildActionGridButton(
                icon: Icons.person_add,
                label: 'Add Student',
                color: const Color(0xFF4DB6AC),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => AddStudentPage(
                        onStudentAdded: () {
                          // Refresh student cache if needed
                          if (widget.adminId != null) {
                            _studentCache.invalidateCache(widget.adminId!);
                          }
                        },
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionGridButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.3), width: 1),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSidebar() {
    return Drawer(
      backgroundColor: Colors.black,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          // Header Section
          DrawerHeader(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.grey[900]!,
                  Colors.black,
                ],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue[700],
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.admin_panel_settings,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Admin Panel',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _sessionName,
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          
          // Group Selection Section
          if (_currentGroupId != null)
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.grey[900],
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Current Group',
                    style: TextStyle(
                      color: Colors.grey[400],
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _currentGroupName ?? 'Unknown',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          
          const Divider(color: Colors.grey, height: 1),
          
          // Menu Items
          _buildMenuItem(
            icon: Icons.group_add,
            title: 'Create Group',
            index: 0,
            onTap: () {
              Navigator.pop(context);
              _showCreateGroupDialog();
            },
          ),
          
          _buildMenuItem(
            icon: Icons.folder,
            title: 'My Groups',
            index: 1,
            onTap: () {
              Navigator.pop(context);
              _showMyGroupsDialog();
            },
          ),
          
          const Divider(color: Colors.grey, height: 16),
          
          _buildMenuItem(
            icon: Icons.dashboard,
            title: 'Dashboard',
            index: 2,
            onTap: () {
              Navigator.pop(context);
              setState(() {
                _selectedIndex = 2;
              });
            },
          ),
          
          _buildMenuItem(
            icon: Icons.group,
            title: 'View Group Students',
            index: 3,
            onTap: () {
              Navigator.pop(context);
              if (_currentGroupId != null) {
                // Show students in selected group
                _showGroupStudentsDialog(_currentGroupId!, _currentGroupName ?? 'Group');
              } else {
                // No group selected - show message
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please select a group first'),
                    backgroundColor: Colors.orange,
                  ),
                );
              }
            },
          ),
          
          _buildMenuItem(
            icon: Icons.people,
            title: 'View All Students',
            index: 4,
            onTap: () {
              Navigator.pop(context);
              _showAllStudentsDialog();
            },
          ),
          
          _buildMenuItem(
            icon: Icons.location_on,
            title: 'Student Locations',
            index: 5,
            onTap: () {
              Navigator.pop(context);
              if (_adminLocation != null) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ViewStudentLocationsPage(
                      adminLocation: LatLng(
                        _adminLocation!.latitude,
                        _adminLocation!.longitude,
                      ),
                      thresholdMeters: _thresholdMeters,
                    ),
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please record your location first'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
          ),
          
          _buildMenuItem(
            icon: Icons.broadcast_on_personal,
            title: 'Broadcast Message',
            index: 9,
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => BroadcastMessagePage(
                    adminId: widget.adminId ?? '',
                    groupId: _currentGroupId,
                    groupName: _currentGroupName,
                    groups: _myGroups,
                  ),
                ),
              );
            },
          ),
          
          _buildMenuItem(
            icon: Icons.analytics,
            title: 'Statistics',
            index: 5,
            onTap: () {
              Navigator.pop(context);
              _showStatisticsDialog();
            },
          ),
          
          _buildMenuItem(
            icon: Icons.download,
            title: 'Export Data',
            index: 6,
            onTap: () {
              Navigator.pop(context);
              _downloadCSV();
            },
          ),
          
          _buildMenuItem(
            icon: Icons.settings,
            title: 'Settings',
            index: 7,
            onTap: () {
              Navigator.pop(context);
              _showSettingsDialog();
            },
          ),
          
          const Divider(color: Colors.grey, height: 32),
          
          _buildMenuItem(
            icon: Icons.logout,
            title: 'Logout',
            index: 8,
            onTap: () {
              Navigator.pop(context);
              _handleLogout();
            },
            isDestructive: true,
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    required int index,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    final isSelected = _selectedIndex == index;
    final color = isDestructive 
        ? Colors.red[400] 
        : (isSelected ? Colors.blue[400]! : Colors.white);
    
    return ListTile(
      leading: Icon(
        icon,
        color: color,
        size: 24,
      ),
      title: Text(
        title,
        style: TextStyle(
          color: color,
          fontSize: 16,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      selected: isSelected,
      selectedTileColor: Colors.grey[900],
      onTap: onTap,
      hoverColor: Colors.grey[900],
    );
  }

  void _showAllStudentsDialog() {
    // Reset pagination when opening dialog
    setState(() {
      _currentPage = 1;
      _hasMore = false;
    });
    
    // Show cached data immediately if available (optimistic UI)
    final cacheIsEmpty = _cachedStudents == null || _cachedStudents!.isEmpty;
    final cacheIsStale = _lastStudentsFetchTime == null || 
                         DateTime.now().difference(_lastStudentsFetchTime!) >= _studentsCacheDuration;
    final needsRefresh = cacheIsEmpty || cacheIsStale;
    
    if (!cacheIsEmpty && !cacheIsStale) {
      // Use cached data immediately
      setState(() {
        _allStudents = List<Student>.from(_cachedStudents!);
        _isLoadingStudents = false;
      });
    } else {
      // Show loading if no cache
      setState(() {
        _allStudents = null;
        _isLoadingStudents = true;
      });
    }
    
    // Show dialog immediately, then fetch data in background
    _studentsScrollController.addListener(_onScroll);
    
    // Fetch data asynchronously (only if needed)
    if (needsRefresh) {
      _fetchAllStudents(loadMore: false, forceRefresh: needsRefresh);
    }
    
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: MediaQuery.of(context).size.width * 0.9,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.8,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.people, color: Colors.white, size: 28),
                    const SizedBox(width: 12),
                    const Text(
                      'All Students',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    if (_allStudents != null && _allStudents!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Text(
                          'Page $_currentPage/$_totalPages',
                          style: TextStyle(
                            color: Colors.grey[300],
                            fontSize: 12,
                          ),
                        ),
                      ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () {
                        _studentsScrollController.removeListener(_onScroll);
                        Navigator.pop(context);
                      },
                    ),
                  ],
                ),
              ),
              
              // Content with RefreshIndicator and Flexible (removed shrinkWrap for better performance)
              Flexible(
                child: RefreshIndicator(
                  onRefresh: () async {
                    setState(() {
                      _currentPage = 1;
                      _allStudents = null;
                      _hasMore = false;
                      // Invalidate cache on refresh
                      _cachedStudents = null;
                      _lastStudentsFetchTime = null;
                    });
                    await _fetchAllStudents(loadMore: false, forceRefresh: true);
                  },
                  child: _isLoadingStudents && _allStudents == null
                      ? const Padding(
                          padding: EdgeInsets.all(40),
                          child: CustomLoader(color: Colors.black),
                        )
                      : _allStudents == null || _allStudents!.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.all(40),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.people_outline, size: 64, color: Colors.grey[400]),
                                  const SizedBox(height: 16),
                                  Text(
                                    'No students found',
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 16,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : ListView.separated(
                              controller: _studentsScrollController,
                              itemCount: _allStudents!.length + (_hasMore ? 1 : 0),
                              separatorBuilder: (context, index) => const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                // Load more indicator at the end
                                if (index == _allStudents!.length) {
                                  return Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Center(
                                      child: _isLoadingStudents
                                          ? const CustomLoader(color: Colors.black)
                                          : TextButton(
                                              onPressed: _loadMoreStudents,
                                              child: const Text('Load More'),
                                            ),
                                    ),
                                  );
                                }
                                // Use StudentCard widget with RepaintBoundary
                                return StudentCard(student: _allStudents![index]);
                              },
                            ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showStatisticsDialog() {
    final totalStudents = _allStudents?.length ?? 0;
    final presentCount = _allStudents?.where((s) => s.isPresent).length ?? 0;
    final absentCount = totalStudents - presentCount;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.analytics, color: Colors.blue),
            SizedBox(width: 8),
            Text('Statistics'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStatCard('Total Students', totalStudents.toString(), Colors.blue),
            const SizedBox(height: 12),
            _buildStatCard('Present', presentCount.toString(), Colors.green),
            const SizedBox(height: 12),
            _buildStatCard('Absent', absentCount.toString(), Colors.red),
            if (totalStudents > 0) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Attendance Rate: ${((presentCount / totalStudents) * 100).toStringAsFixed(1)}%',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[700],
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.settings, color: Colors.blue),
            SizedBox(width: 8),
            Text('Settings'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Session Name: $_sessionName'),
            const SizedBox(height: 16),
            Text('Threshold: ${_thresholdMeters.toStringAsFixed(0)} meters'),
            const SizedBox(height: 16),
            Text('Window Duration: 10 minutes'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showEditSessionNameDialog() {
    final TextEditingController controller = TextEditingController(text: _sessionName);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.edit, color: Colors.blue),
            SizedBox(width: 8),
            Text('Edit Session Name'),
          ],
        ),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Session Name',
            hintText: 'Enter session name',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isNotEmpty && newName != _sessionName) {
                Navigator.pop(context);
                await _updateSessionName(newName);
              } else if (newName.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Session name cannot be empty'),
                    backgroundColor: Colors.red,
                  ),
                );
              } else {
                Navigator.pop(context);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _updateSessionName(String newName) async {
    try {
      final body = <String, String>{
        'session_name': newName,
      };
      
      if (_currentGroupId != null) {
        body['group_id'] = _currentGroupId!;
      }
      
      final response = await http.post(
        Uri.parse(ApiConfig.updateSessionName),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: body,
      );

      if (response.statusCode == 200) {
        setState(() {
          _sessionName = newName;
        });
        
        // Update group name if group is selected
        if (_currentGroupId != null && _myGroups != null) {
          final groupIndex = _myGroups!.indexWhere((g) => g['id'] == _currentGroupId);
          if (groupIndex != -1) {
            setState(() {
              _myGroups![groupIndex]['name'] = newName;
              _currentGroupName = newName;
            });
          }
        }
        
        // Save state after updating session name
        _saveState();
        
        if (mounted) {
          HapticFeedback.mediumImpact();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Session name updated to "$newName"'),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
        }
      } else {
        final error = response.body.isNotEmpty 
            ? json.decode(response.body)['error'] ?? 'Failed to update session name'
            : 'Failed to update session name';
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(error),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final dateFormat = DateFormat('EEEE, MMMM d, y');
    final timeFormat = DateFormat('h:mm a');
    
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: CustomScrollView(
        slivers: [
          // Enhanced Header
          SliverAppBar(
            expandedHeight: 140,
            floating: false,
            pinned: true,
            elevation: 4,
            shadowColor: Colors.black.withOpacity(0.2),
            backgroundColor: Colors.white,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.only(left: 16, bottom: 16, right: 16),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.adminUsername != null && widget.adminUsername!.isNotEmpty
                              ? '${widget.adminUsername![0].toUpperCase()}${widget.adminUsername!.substring(1)} Dashboard'
                              : 'Admin Dashboard',
                          style: const TextStyle(
                            color: Color(0xFF212121),
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Flexible(
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  '${dateFormat.format(now)} • ',
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              GestureDetector(
                                onTap: () => _showEditSessionNameDialog(),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Flexible(
                                      child: Text(
                                        _sessionName,
                                        style: TextStyle(
                                          color: Colors.blue[700],
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Icon(
                                      Icons.edit,
                                      size: 14,
                                      color: Colors.blue[700],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Logout
                      IconButton(
                        icon: Icon(Icons.logout, color: Colors.grey[700]),
                        onPressed: _handleLogout,
                        tooltip: 'Logout',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // Body Content
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Action Buttons Grid
                  _buildActionButtonsGrid(),
                  const SizedBox(height: 24),
                  
                  // Session Setup Section
                  _buildSectionCard(
                    title: 'SESSION SETUP',
                    icon: Icons.settings,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 8),
                        TextField(
                          decoration: InputDecoration(
                            labelText: 'Session Name',
                            hintText: 'e.g., Workshop_Day2',
                            prefixIcon: Icon(Icons.event, color: Colors.blue[700]),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            filled: true,
                            fillColor: Colors.grey[50],
                          ),
                          onChanged: (value) {
                            setState(() {
                              _sessionName = value.isEmpty ? 'Workshop_Day2' : value;
                            });
                          },
                          controller: TextEditingController(text: _sessionName),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.radio_button_checked, color: Colors.blue[700], size: 20),
                                const SizedBox(width: 8),
                                Text(
                                  'Threshold: ${_thresholdMeters.toStringAsFixed(0)}m',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey[800],
                                  ),
                                ),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.blue[50],
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '${_thresholdMeters.toStringAsFixed(0)}m',
                                style: TextStyle(
                                  color: Colors.blue[700],
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Slider(
                          value: _thresholdMeters,
                          min: 50,
                          max: 300,
                          divisions: 25,
                          activeColor: Colors.blue[700],
                          onChanged: (value) {
                            HapticFeedback.selectionClick();
                            setState(() {
                              _thresholdMeters = value;
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Step 1: Record Location
                  _buildSectionHeader(
                    step: 'STEP 1',
                    title: 'RECORD LOCATION',
                    icon: Icons.location_on,
                  ),
                  const SizedBox(height: 16),
                  _buildActionButton(
                    onPressed: _isRecordingLocation ? null : _recordLocation,
                    isLoading: _isRecordingLocation,
                    icon: Icons.location_on,
                    label: 'RECORD MY LOCATION',
                    gradient: LinearGradient(
                      colors: [Colors.blue[600]!, Colors.blue[400]!],
                    ),
                  ),
                  if (_adminLocation != null) ...[
                    const SizedBox(height: 20),
                    // Enhanced Location Card
                    _buildLocationCard(),
                    const SizedBox(height: 20),
                    // Enhanced Map
                    _buildMapCard(),
                  ],
            const SizedBox(height: 24),

                  // Attendance Scope Toggle (NEW)
                  if (_currentGroupId != null) ...[
                    _buildSectionHeader(
                      step: 'ATTENDANCE SCOPE',
                      title: 'SELECT ATTENDANCE MODE',
                      icon: Icons.group,
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          RadioListTile<bool>(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                            title: const Text(
                              'Group Only',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                'Only students in "${_currentGroupName ?? "selected group"}" can submit attendance',
                                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            value: true,
                            groupValue: _attendanceScopeGroupOnly,
                            onChanged: (value) {
                              setState(() {
                                _attendanceScopeGroupOnly = value ?? true;
                              });
                            },
                            activeColor: Colors.blue[700],
                          ),
                          const Divider(height: 1),
                          RadioListTile<bool>(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                            title: const Text(
                              'All Students',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                'All students in the system can submit attendance',
                                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            value: false,
                            groupValue: _attendanceScopeGroupOnly,
                            onChanged: (value) {
                              setState(() {
                                _attendanceScopeGroupOnly = value ?? false;
                              });
                            },
                            activeColor: Colors.blue[700],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Step 2: Start Attendance Window
                  _buildSectionHeader(
                    step: 'STEP 2',
                    title: 'START ATTENDANCE',
                    icon: Icons.timer,
                  ),
                  const SizedBox(height: 16),
                  _buildActionButton(
                    onPressed: (_isStartingWindow || _adminLocation == null || _attendanceActive)
                        ? null
                        : _startWindow,
                    isLoading: _isStartingWindow,
                    icon: Icons.timer,
                    label: _attendanceActive ? 'WINDOW ACTIVE' : 'START 10-MIN WINDOW',
                    gradient: _attendanceActive
                        ? LinearGradient(colors: [Colors.orange[600]!, Colors.orange[400]!])
                        : LinearGradient(colors: [Colors.green[600]!, Colors.green[400]!]),
                  ),
                  if (_attendanceActive) ...[
                    const SizedBox(height: 20),
                    _buildTimerCard(context),
                  ],
                  const SizedBox(height: 24),

                  // Step 3: Check Student Locations
                  _buildSectionHeader(
                    step: 'STEP 3',
                    title: 'CHECK LOCATIONS',
                    icon: Icons.location_searching,
                  ),
                  const SizedBox(height: 16),
                  _buildActionButton(
                    onPressed: _adminLocation == null
                        ? null
                        : () {
                            HapticFeedback.mediumImpact();
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ViewStudentLocationsPage(
                                  adminLocation: LatLng(
                                    _adminLocation!.latitude,
                                    _adminLocation!.longitude,
                                  ),
                                  thresholdMeters: _thresholdMeters,
                                  groupId: _currentGroupId,
                                ),
                              ),
                            );
                          },
                    isLoading: false,
                    icon: Icons.location_searching,
                    label: 'CHECK LOCATIONS',
                    gradient: LinearGradient(colors: [Colors.purple[600]!, Colors.purple[400]!]),
                  ),
                  const SizedBox(height: 24),

                  // Step 4: Download CSV
                  _buildSectionHeader(
                    step: 'STEP 4',
                    title: 'DOWNLOAD RESULTS',
                    icon: Icons.download,
                  ),
                  const SizedBox(height: 16),
                  _buildActionButton(
                    onPressed: _isDownloading ? null : _downloadCSV,
                    isLoading: _isDownloading,
                    icon: Icons.download,
                    label: 'DOWNLOAD ATTENDANCE CSV',
                    gradient: LinearGradient(colors: [Colors.orange[600]!, Colors.orange[400]!]),
                  ),
                  const SizedBox(height: 32),
                  
                  // Broadcast Message Button
                  _buildActionButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => BroadcastMessagePage(
                            adminId: widget.adminId ?? '',
                            groupId: _currentGroupId,
                            groupName: _currentGroupName,
                            groups: _myGroups,
                          ),
                        ),
                      );
                    },
                    isLoading: false,
                    icon: Icons.broadcast_on_personal,
                    label: 'BROADCAST MESSAGE',
                    gradient: LinearGradient(colors: [Colors.red[600]!, Colors.red[400]!]),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Helper Widget Builders
  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: Colors.blue[700], size: 20),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader({
    required String step,
    required String title,
    required IconData icon,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [Colors.blue[600]!, Colors.blue[400]!]),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            step,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 11,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Icon(icon, color: Colors.blue[700], size: 20),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.grey[800],
              letterSpacing: 0.3,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required VoidCallback? onPressed,
    required bool isLoading,
    required IconData icon,
    required String label,
    required Gradient gradient,
  }) {
    return Container(
      height: 60,
      decoration: BoxDecoration(
        gradient: onPressed == null ? null : gradient,
        color: onPressed == null ? Colors.grey[300] : null,
        borderRadius: BorderRadius.circular(16),
        boxShadow: onPressed == null
            ? null
            : [
                BoxShadow(
                  color: (gradient.colors.first as Color).withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isLoading)
                  const CustomLoaderSmall(color: Colors.white)
                else
                  Icon(icon, color: Colors.white, size: 22),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.3,
                    ),
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLocationCard() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.green[50]!, Colors.green[100]!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.green.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.green[600],
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check_circle,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Location Recorded',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: Colors.green[900],
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: Icon(Icons.refresh, color: Colors.green[700]),
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    _recordLocation();
                  },
                  tooltip: 'Refresh Location',
                ),
              ],
            ),
            const SizedBox(height: 16),
            Divider(color: Colors.green[200]),
            const SizedBox(height: 16),
            _buildCoordinateRow(
              'Latitude',
              CoordinateFormatter.formatSimple(_adminLocation!.latitude, true),
              Icons.explore,
            ),
            const SizedBox(height: 12),
            _buildCoordinateRow(
              'Longitude',
              CoordinateFormatter.formatSimple(_adminLocation!.longitude, false),
              Icons.explore,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.gps_fixed, color: Colors.green[700], size: 18),
                const SizedBox(width: 8),
                Text(
                  'Accuracy: ±${_adminLocation!.accuracy.toStringAsFixed(0)}m',
                  style: TextStyle(
                    color: Colors.green[800],
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCoordinateRow(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: Colors.green[700], size: 18),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: TextStyle(
            color: Colors.green[800],
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: Colors.green[900],
              fontSize: 14,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMapCard() {
    return MouseRegion(
      onEnter: (_) => setState(() => _isMapHovered = true),
      onExit: (_) => setState(() => _isMapHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(_isMapHovered ? 0.25 : 0.1),
              blurRadius: _isMapHovered ? 15 : 10,
              offset: Offset(0, _isMapHovered ? 8 : 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                height: _isMapHovered ? 400 : 254,
                child: FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: LatLng(
                      _adminLocation!.latitude,
                      _adminLocation!.longitude,
                    ),
                    initialZoom: 16.0,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.attendance.attendance_system',
                    ),
                    CircleLayer(
                      circles: [
                        CircleMarker(
                          point: LatLng(
                            _adminLocation!.latitude,
                            _adminLocation!.longitude,
                          ),
                          radius: _thresholdMeters,
                          color: Colors.green.withOpacity(0.15),
                          borderColor: Colors.green[600]!,
                          borderStrokeWidth: 2,
                          useRadiusInMeter: true,
                        ),
                      ],
                    ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: LatLng(
                            _adminLocation!.latitude,
                            _adminLocation!.longitude,
                          ),
                          width: 40,
                          height: 40,
                          child: const Icon(
                            Icons.location_on,
                            color: Colors.blue,
                            size: 40,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            // Fullscreen icon - top right, no card, just icon
            Positioned(
              top: _isMapHovered ? 16 : -50,
              right: 16,
              child: AnimatedOpacity(
                opacity: _isMapHovered ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      HapticFeedback.mediumImpact();
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => FullScreenMapPage(
                            adminLocation: LatLng(
                              _adminLocation!.latitude,
                              _adminLocation!.longitude,
                            ),
                            thresholdMeters: _thresholdMeters,
                            mapController: _mapController,
                          ),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Icon(
                        Icons.fullscreen,
                        color: Colors.blue[700],
                        size: 32,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Zoom Controls - appear on hover, positioned to avoid overlap
            Positioned(
              right: 16,
              bottom: _isMapHovered ? 70 : -80,
              child: AnimatedOpacity(
                opacity: _isMapHovered ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildZoomButton(Icons.add, () {
                      HapticFeedback.selectionClick();
                      _mapController.move(_mapController.camera.center, _mapController.camera.zoom + 1);
                    }),
                    const SizedBox(height: 8),
                    _buildZoomButton(Icons.remove, () {
                      HapticFeedback.selectionClick();
                      _mapController.move(_mapController.camera.center, _mapController.camera.zoom - 1);
                    }),
                  ],
                ),
              ),
            ),
            // Compass - always visible but subtle
            Positioned(
              left: 16,
              bottom: 16,
              child: AnimatedOpacity(
                opacity: _isMapHovered ? 1.0 : 0.6,
                duration: const Duration(milliseconds: 300),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(_isMapHovered ? 0.95 : 0.8),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(_isMapHovered ? 0.3 : 0.15),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: Icon(Icons.explore, color: Colors.blue[700], size: _isMapHovered ? 24 : 20),
                ),
              ),
            ),
            // Label at bottom (like the CSS design)
            Positioned(
              bottom: 8,
              left: 20,
              child: AnimatedOpacity(
                opacity: _isMapHovered ? 0.0 : 1.0,
                duration: const Duration(milliseconds: 300),
                child: Text(
                  '--- Location Map ---',
                  style: TextStyle(
                    letterSpacing: 0.2,
                    color: Colors.grey[700],
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }

  Widget _buildZoomButton(IconData icon, VoidCallback onPressed) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
          ),
        ],
      ),
      child: IconButton(
        icon: Icon(icon, color: Colors.blue[700]),
        onPressed: () {
          HapticFeedback.selectionClick();
          onPressed();
        },
      ),
    );
  }

  Widget _buildTimerCard(BuildContext context) {
    if (!mounted) return const SizedBox.shrink();
    
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 500),
      builder: (context, value, child) {
        if (!mounted) return const SizedBox.shrink();
        return Transform.scale(
          scale: value,
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.timer, color: Colors.orange[700], size: 24),
                      const SizedBox(width: 8),
                      Text(
                        'WINDOW ACTIVE',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange[900],
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      // Pulse Animation - using a simple container with opacity animation
                      if (_attendanceActive && mounted)
                        Container(
                          width: MediaQuery.of(context).size.width / 2 + 20,
                          height: MediaQuery.of(context).size.width / 2 + 20,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.orange.withOpacity(0.15),
                          ),
                        ),
                      CircularCountDownTimer(
                        duration: _attendanceActive && _remainingSeconds > 0 ? _remainingSeconds : 600,
                        initialDuration: _attendanceActive && _remainingSeconds > 0 ? _remainingSeconds : 0,
                        controller: _countDownController,
                        width: MediaQuery.of(context).size.width / 2,
                        height: MediaQuery.of(context).size.width / 2,
                        ringColor: Colors.grey[300]!,
                        ringGradient: LinearGradient(
                          colors: [Colors.lightBlue[300]!, Colors.lightBlue[100]!],
                        ),
                        fillColor: Colors.lightBlue[200]!,
                        fillGradient: LinearGradient(
                          colors: [Colors.lightBlue[400]!, Colors.lightBlue[200]!],
                        ),
                        backgroundColor: Colors.lightBlue[500],
                        backgroundGradient: LinearGradient(
                          colors: [Colors.lightBlue[600]!, Colors.lightBlue[400]!],
                        ),
                        strokeWidth: 20.0,
                        strokeCap: StrokeCap.round,
                        textStyle: const TextStyle(
                          fontSize: 33.0,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                        textFormat: CountdownTextFormat.MM_SS,
                        isReverse: true,
                        isReverseAnimation: true,
                        isTimerTextShown: true,
                        autoStart: false,
                        onStart: () => debugPrint('Countdown Started'),
                        onComplete: () => debugPrint('Countdown Ended'),
                        onChange: (String timeStamp) => debugPrint('Countdown Changed $timeStamp'),
                        timeFormatterFunction: (defaultFormatterFunction, duration) {
                          if (duration.inSeconds == 0) {
                            return "00:00";
                          } else {
                            return Function.apply(defaultFormatterFunction, [duration]);
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  // Abort Button
                  Container(
                    width: double.infinity,
                    height: 50,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.red.withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ElevatedButton.icon(
                      onPressed: () {
                        HapticFeedback.mediumImpact();
                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Abort Attendance Window?'),
                            content: const Text(
                              'Are you sure you want to close the attendance window? This action cannot be undone.',
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Cancel'),
                              ),
                              ElevatedButton(
                                onPressed: () {
                                  Navigator.pop(context);
                                  _closeWindow();
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                  foregroundColor: Colors.white,
                                ),
                                child: const Text('Abort'),
                              ),
                            ],
                          ),
                        );
                      },
                      icon: const Icon(Icons.stop_circle, size: 20),
                      label: const Text(
                        'Abort Timer',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red[600],
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_windowStartTime != null && _windowEndTime != null) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Column(
                          children: [
                            Text(
                              'Started',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              DateFormat('h:mm a').format(_windowStartTime!),
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.orange[900],
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        Container(
                          width: 1,
                          height: 30,
                          color: Colors.orange[300],
                        ),
                        Column(
                          children: [
                            Text(
                              'Ends',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              DateFormat('h:mm a').format(_windowEndTime!),
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.orange[900],
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
        );
      },
    );
  }

  Future<void> _fetchMyGroups({bool forceRefresh = false}) async {
    if (widget.adminId == null) {
      debugPrint('DEBUG: _fetchMyGroups - adminId is null, returning');
      return;
    }
    
    debugPrint('DEBUG: _fetchMyGroups - forceRefresh: $forceRefresh, cachedGroups: ${_cachedGroups?.length ?? 0}, lastFetch: $_lastGroupsFetchTime');
    
    // Phase 1 Optimization: Check frontend cache first (0ms load time!)
    // Only skip network call if cache is fresh AND we're not forcing refresh
    if (!forceRefresh && 
        _cachedGroups != null && 
        _cachedGroups!.isNotEmpty &&
        _lastGroupsFetchTime != null &&
        DateTime.now().difference(_lastGroupsFetchTime!) < _groupsCacheDuration) {
      // Cache is fresh - use it immediately (no network call = 0ms, 0 battery!)
      debugPrint('DEBUG: _fetchMyGroups - Using cached data (no network call)');
      if (mounted) {
        setState(() {
          _myGroups = List<Map<String, dynamic>>.from(_cachedGroups!);
          _isLoadingGroups = false;
        });
      }
      return; // ✅ No network call!
    }
    
    debugPrint('DEBUG: _fetchMyGroups - Making network request to backend');
    
    // Show cached data immediately if available (optimistic UI)
    if (_cachedGroups != null && _cachedGroups!.isNotEmpty && mounted) {
      setState(() {
        _myGroups = List<Map<String, dynamic>>.from(_cachedGroups!);
      });
    }
    
    // Show loading only if cache is empty
    if (_cachedGroups == null || _cachedGroups!.isEmpty) {
      if (mounted) {
        setState(() {
          _isLoadingGroups = true;
        });
      }
    }

    try {
      // Add cache bust parameter only if force refresh
      final cacheBust = forceRefresh ? '&_t=${DateTime.now().millisecondsSinceEpoch}' : '';
      final url = '${ApiConfig.getMyGroups}?admin_id=${widget.adminId}$cacheBust';
      debugPrint('DEBUG: _fetchMyGroups - Requesting URL: $url');
      final response = await _httpClient.get(Uri.parse(url));
      debugPrint('DEBUG: _fetchMyGroups - Response status: ${response.statusCode}, body length: ${response.body.length}');
      
      if (response.statusCode == 200 && response.body.isNotEmpty) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        if (mounted && data.containsKey('groups')) {
          final groups = List<Map<String, dynamic>>.from(data['groups']);
          setState(() {
            _myGroups = groups;
            _cachedGroups = groups; // Update cache
            _lastGroupsFetchTime = DateTime.now(); // Update timestamp
            _isLoadingGroups = false;
          });
        }
      } else {
        // Fallback to cached data on error
        if (_cachedGroups != null && _cachedGroups!.isNotEmpty && mounted) {
          setState(() {
            _myGroups = List<Map<String, dynamic>>.from(_cachedGroups!);
            _isLoadingGroups = false;
          });
        } else if (mounted) {
          setState(() {
            _isLoadingGroups = false;
          });
        }
      }
    } catch (e) {
      debugPrint('Error fetching groups: $e');
      // Fallback to cached data on error (offline mode)
      if (_cachedGroups != null && _cachedGroups!.isNotEmpty && mounted) {
        setState(() {
          _myGroups = List<Map<String, dynamic>>.from(_cachedGroups!);
          _isLoadingGroups = false;
        });
        // Optional: Show subtle indicator that cached data is being used
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Using cached data'),
            duration: Duration(seconds: 2),
            backgroundColor: Colors.orange,
          ),
        );
      } else if (mounted) {
        setState(() {
          _isLoadingGroups = false;
        });
      }
    }
  }

  void _showCreateGroupDialog() async {
    final groupNameController = TextEditingController();
    final selectedStudentIds = <String>{};
    
    // Fetch students if not already loaded (force refresh to get latest data)
    if (_allStudents == null && !_isLoadingStudents) {
      await _fetchAllStudents(forceRefresh: true);
    }

    if (!mounted) return;
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            width: MediaQuery.of(context).size.width * 0.9,
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.8,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.group_add, color: Colors.white, size: 22),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          'Create New Group',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white, size: 20),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: groupNameController,
                          decoration: InputDecoration(
                            labelText: 'Group Name',
                            hintText: 'e.g., Workshop Day 1',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            prefixIcon: const Icon(Icons.label, size: 20),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          ),
                          style: const TextStyle(fontSize: 14),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Select Students',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Flexible(
                          child: Builder(
                            builder: (context) {
                              // This Builder will rebuild when parent state changes
                              if (_isLoadingStudents) {
                                return const Padding(
                                  padding: EdgeInsets.all(40),
                                  child: Center(child: CustomLoader(color: Colors.black)),
                                );
                              }
                              if (_allStudents == null || _allStudents!.isEmpty) {
                                return const Center(child: Text('No students available'));
                              }
                              return ListView.builder(
                                shrinkWrap: true,
                                itemCount: _allStudents!.length,
                                itemBuilder: (context, index) {
                                  final student = _allStudents![index];
                                  final isSelected = selectedStudentIds.contains(student.id);
                                  
                                  return CheckboxListTile(
                                    dense: true,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    title: Text(
                                      student.name,
                                      style: const TextStyle(fontSize: 14),
                                    ),
                                    subtitle: Text(
                                      'ID: ${student.id}',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    value: isSelected,
                                    onChanged: (value) {
                                      setDialogState(() {
                                        if (value == true) {
                                          selectedStudentIds.add(student.id);
                                        } else {
                                          selectedStudentIds.remove(student.id);
                                        }
                                      });
                                    },
                                  );
                                },
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(16),
                      bottomRight: Radius.circular(16),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () {
                          Navigator.pop(context);
                        },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        ),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(fontSize: 14),
                        ),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton(
                        onPressed: () async {
                          if (groupNameController.text.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Please enter a group name')),
                            );
                            return;
                          }
                          if (selectedStudentIds.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Please select at least one student')),
                            );
                            return;
                          }
                          
                          await _createGroup(
                            groupNameController.text,
                            selectedStudentIds.toList(),
                          );
                          Navigator.pop(context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        ),
                        child: const Text(
                          'Create Group',
                          style: TextStyle(fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _createGroup(String name, List<String> studentIds) async {
    if (widget.adminId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Admin ID not found. Please login again.')),
      );
      return;
    }

    // Phase 1 Optimization: Optimistic update - add temporary group to UI immediately
    final tempGroup = {
      'id': 'temp_${DateTime.now().millisecondsSinceEpoch}',
      'name': name,
      'status': 'inactive',
      'created_at': DateTime.now().toIso8601String(),
      'isOptimistic': true, // Flag for UI
    };
    
    // Immediately add to UI (instant feedback!)
    if (mounted) {
      setState(() {
        _myGroups ??= [];
        _myGroups!.insert(0, tempGroup);
        _cachedGroups ??= [];
        _cachedGroups!.insert(0, tempGroup);
      });
    }

    try {
      final createResponse = await _httpClient.post(
        Uri.parse(ApiConfig.createGroup),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'name': name,
          'admin_id': widget.adminId!,
        },
      );

      // Check if response body is not empty before parsing
      if (createResponse.body.isEmpty) {
        throw Exception('Empty response from server');
      }

      // Handle different status codes
      if (createResponse.statusCode == 200) {
        try {
          final createData = json.decode(createResponse.body);
          if (createData is Map && createData.containsKey('group')) {
            final groupId = createData['group']['id'] as String;
            
            // Add students to the group
            final addResponse = await _httpClient.post(
              Uri.parse(ApiConfig.addStudentsToGroup),
              headers: {'Content-Type': 'application/x-www-form-urlencoded'},
              body: {
                'group_id': groupId,
                'student_ids': studentIds.join(','),
              },
            );

            if (addResponse.statusCode == 200) {
              // Try to parse the response if it's not empty
              String errorMessage = '';
              if (addResponse.body.isNotEmpty) {
                try {
                  final addData = json.decode(addResponse.body);
                  if (addData is Map && addData.containsKey('error')) {
                    errorMessage = addData['error'] as String? ?? '';
                  }
                } catch (_) {
                  // Response might not be JSON, ignore
                }
              }

              if (errorMessage.isEmpty) {
                // Replace temp group with real group data
                final realGroup = {
                  'id': groupId,
                  'name': name,
                  'status': 'inactive',
                  'created_at': DateTime.now().toIso8601String(),
                };
                
                setState(() {
                  _currentGroupId = groupId;
                  _currentGroupName = name;
                  
                  // Remove temp group and add real one
                  _myGroups?.removeWhere((g) => g['id'] == tempGroup['id']);
                  _myGroups?.insert(0, realGroup);
                  
                  // Save state
                  _saveState();
                  
                  // Fetch location and window status for the selected group
                  _fetchAdminLocation();
                  _fetchWindowStatus();
                  
                  // Update cache
                  _cachedGroups?.removeWhere((g) => g['id'] == tempGroup['id']);
                  _cachedGroups?.insert(0, realGroup);
                  _lastGroupsFetchTime = DateTime.now(); // Refresh cache timestamp
                });
                
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Group "$name" created successfully!'),
                    backgroundColor: Colors.green,
                    duration: const Duration(seconds: 2),
                  ),
                );
                
                // Invalidate cache to refresh student-group relationships
                _studentCache.invalidateCache(widget.adminId ?? '');
              } else {
                throw Exception(errorMessage);
              }
            } else {
              // Parse error message from response
              String errorMsg = 'Failed to add students to group (Status: ${addResponse.statusCode})';
              if (addResponse.body.isNotEmpty) {
                try {
                  final errorData = json.decode(addResponse.body);
                  if (errorData is Map && errorData.containsKey('error')) {
                    errorMsg = errorData['error'] as String? ?? errorMsg;
                  }
                } catch (_) {
                  errorMsg = addResponse.body;
                }
              }
              throw Exception(errorMsg);
            }
          } else {
            throw Exception('Invalid response format: group data not found');
          }
        } catch (e) {
          if (e is FormatException) {
            throw Exception('Invalid JSON response from server: ${createResponse.body}');
          }
          rethrow;
        }
      } else {
        // Parse error message from non-200 response
        String errorMsg = 'Failed to create group (Status: ${createResponse.statusCode})';
        if (createResponse.body.isNotEmpty) {
          try {
            final errorData = json.decode(createResponse.body);
            if (errorData is Map && errorData.containsKey('error')) {
              errorMsg = errorData['error'] as String? ?? errorMsg;
              if (errorData.containsKey('details')) {
                errorMsg += ': ${errorData['details']}';
              }
            }
          } catch (_) {
            // If not JSON, use the raw body
            errorMsg = createResponse.body;
          }
        }
        throw Exception(errorMsg);
      }
    } catch (e) {
      // Rollback optimistic update on error
      if (mounted) {
        setState(() {
          _myGroups?.removeWhere((g) => g['id'] == tempGroup['id']);
          _cachedGroups?.removeWhere((g) => g['id'] == tempGroup['id']);
        });
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error creating group: ${e.toString()}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  void _showMyGroupsDialog() {
    // Show dialog immediately with cached data (if available)
    // Always fetch if cache is empty, or if cache is stale (smart refresh)
    final cacheIsEmpty = _cachedGroups == null || _cachedGroups!.isEmpty;
    final cacheIsStale = _lastGroupsFetchTime == null || 
                         DateTime.now().difference(_lastGroupsFetchTime!) >= _groupsCacheDuration;
    final needsRefresh = cacheIsEmpty || cacheIsStale;
    
    debugPrint('DEBUG: _showMyGroupsDialog - cacheIsEmpty: $cacheIsEmpty, cacheIsStale: $cacheIsStale, needsRefresh: $needsRefresh');
    _fetchMyGroups(forceRefresh: needsRefresh);
    
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: MediaQuery.of(context).size.width * 0.9,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.7,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.folder, color: Colors.white, size: 28),
                    const SizedBox(width: 12),
                    const Text(
                      'My Groups',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: _isLoadingGroups
                    ? const Padding(
                        padding: EdgeInsets.all(40),
                        child: CustomLoader(color: Colors.black),
                      )
                    : _myGroups == null || _myGroups!.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(40),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.folder_outlined, size: 64, color: Colors.grey[400]),
                                const SizedBox(height: 16),
                                Text(
                                  'No groups found',
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton(
                                  onPressed: () {
                                    Navigator.pop(context);
                                    _showCreateGroupDialog();
                                  },
                                  child: const Text('Create Your First Group'),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            itemCount: _myGroups!.length,
                            itemBuilder: (context, index) {
                              final group = _myGroups![index];
                              final groupId = group['id'] as String? ?? '';
                              final groupName = group['name'] as String? ?? 'Unknown';
                              final status = group['status'] as String? ?? 'inactive';
                              final isActive = _currentGroupId == groupId;
                              
                              return Container(
                                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                decoration: BoxDecoration(
                                  color: isActive ? Colors.blue[50] : Colors.grey[50],
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isActive ? Colors.blue[300]! : Colors.grey[300]!,
                                    width: isActive ? 2 : 1,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.05),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                  leading: Icon(
                                    Icons.folder,
                                    color: isActive ? Colors.blue[700] : Colors.grey[600],
                                  ),
                                  title: Text(
                                    groupName,
                                    style: TextStyle(
                                      fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                                      fontSize: 16,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 2,
                                    softWrap: true,
                                  ),
                                  subtitle: Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      'Status: ${status[0].toUpperCase()}${status.substring(1)}',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey[600],
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  onTap: () {
                                    // Click to view students in group
                                    Navigator.pop(context);
                                    _showGroupStudentsDialog(groupId, groupName);
                                  },
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (isActive)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                          decoration: BoxDecoration(
                                            color: Colors.blue[700],
                                            borderRadius: BorderRadius.circular(20),
                                          ),
                                          child: const Text(
                                            'Active',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        )
                                      else
                                        ElevatedButton(
                                          onPressed: () {
                                            setState(() {
                                              _currentGroupId = groupId;
                                              _currentGroupName = groupName;
                                            });
                                            // Save state
                                            _saveState();
                                            // Fetch location and window status for the selected group
                                            _fetchAdminLocation();
                                            _fetchWindowStatus();
                                            Navigator.pop(context);
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(
                                                content: Text('Switched to group: $groupName'),
                                                backgroundColor: Colors.green,
                                              ),
                                            );
                                          },
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.blue[600],
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(20),
                                            ),
                                          ),
                                          child: const Text(
                                            'Select',
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      const SizedBox(width: 8),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                                        onPressed: () => _deleteGroup(groupId, groupName),
                                        tooltip: 'Delete group',
                                        iconSize: 22,
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Show students in a group
  Future<void> _showGroupStudentsDialog(String groupId, String groupName) async {
    bool isLoading = true;
    List<Map<String, dynamic>>? students = null;
    String? errorMessage;

    // Fetch students in the group
    try {
      final response = await _httpClient.get(
        Uri.parse('${ApiConfig.getGroupStudents}?group_id=$groupId'),
      );

      if (response.statusCode == 200 && response.body.isNotEmpty) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        if (data.containsKey('students')) {
          students = List<Map<String, dynamic>>.from(data['students']);
        }
      } else {
        errorMessage = 'Failed to load students';
      }
    } catch (e) {
      errorMessage = 'Error: ${e.toString()}';
    } finally {
      isLoading = false;
    }

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            width: MediaQuery.of(context).size.width * 0.9,
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.7,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.people, color: Colors.white, size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Students in Group',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              groupName,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: isLoading
                      ? const Padding(
                          padding: EdgeInsets.all(40),
                          child: CustomLoader(color: Colors.black),
                        )
                      : errorMessage != null
                          ? Padding(
                              padding: const EdgeInsets.all(40),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
                                  const SizedBox(height: 16),
                                  Text(
                                    errorMessage,
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 16,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : students == null || students.isEmpty
                              ? Padding(
                                  padding: const EdgeInsets.all(40),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.people_outline, size: 64, color: Colors.grey[400]),
                                      const SizedBox(height: 16),
                                      Text(
                                        'No students in this group',
                                        style: TextStyle(
                                          color: Colors.grey[600],
                                          fontSize: 16,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : ListView.builder(
                                  shrinkWrap: true,
                                  itemCount: students!.length,
                                  itemBuilder: (context, index) {
                                    final studentList = students!; // Non-null assertion
                                    final student = studentList[index];
                                    final studentId = student['student_id'] as String? ?? 'N/A';
                                    final studentName = student['student_name'] as String? ?? 'Unknown';

                                    return Container(
                                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: Colors.grey[300]!,
                                          width: 1,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withOpacity(0.05),
                                            blurRadius: 4,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: ListTile(
                                        contentPadding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 8,
                                        ),
                                        leading: CircleAvatar(
                                          radius: 24,
                                          backgroundColor: Colors.blue[100],
                                          child: Text(
                                            studentName.isNotEmpty ? studentName[0].toUpperCase() : '?',
                                            style: TextStyle(
                                              color: Colors.blue[700],
                                              fontWeight: FontWeight.bold,
                                              fontSize: 18,
                                            ),
                                          ),
                                        ),
                                        title: Text(
                                          studentName,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 16,
                                            color: Colors.black87,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 2,
                                          softWrap: true,
                                        ),
                                        subtitle: Padding(
                                          padding: const EdgeInsets.only(top: 4),
                                          child: Text(
                                            'ID: $studentId',
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: Colors.grey[600],
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                ),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(16),
                      bottomRight: Radius.circular(16),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Total: ${students?.length ?? 0} students',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[700],
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Delete a group
  Future<void> _deleteGroup(String groupId, String groupName) async {
    // Show confirmation dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Group'),
        content: Text('Are you sure you want to delete "$groupName"?\n\nThis action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    // Show loading
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
              SizedBox(width: 16),
              Text('Deleting group...'),
            ],
          ),
          duration: Duration(seconds: 2),
        ),
      );
    }

    try {
      final response = await _httpClient.post(
        Uri.parse(ApiConfig.deleteGroup),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {'group_id': groupId},
      );

      if (response.statusCode == 200) {
        // Remove from local cache
        if (mounted) {
          setState(() {
            _myGroups?.removeWhere((g) => g['id'] == groupId);
            _cachedGroups?.removeWhere((g) => g['id'] == groupId);
            
            // If deleted group was active, clear selection
            if (_currentGroupId == groupId) {
              _currentGroupId = null;
              _currentGroupName = null;
            }
          });
          // Save state after deleting group
          _saveState();
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Group "$groupName" deleted successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        final errorData = response.body.isNotEmpty
            ? json.decode(response.body) as Map<String, dynamic>?
            : null;
        final errorMsg = errorData?['error'] as String? ?? 'Failed to delete group';
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMsg),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting group: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

