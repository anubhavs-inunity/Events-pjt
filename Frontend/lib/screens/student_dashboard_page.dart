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
import 'dart:convert';
import 'dart:async';
import '../config/api_config.dart';
import '../widgets/custom_loader.dart';
import '../widgets/animated_message_notification.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import 'unified_login_page.dart';
import 'student_messages_page.dart';
import 'fullscreen_map_page.dart';

class StudentDashboardPage extends StatefulWidget {
  final String studentId;
  final String studentName;

  const StudentDashboardPage({
    super.key,
    required this.studentId,
    required this.studentName,
  });

  @override
  State<StudentDashboardPage> createState() => _StudentDashboardPageState();
}

class _StudentDashboardPageState extends State<StudentDashboardPage> {
  String? _submissionStatus; // "pending", "submitted"
  Map<String, dynamic>? _attendanceResult;
  bool _isSubmitting = false;
  
  // Map and timer state
  LatLng? _adminLocation;
  LatLng? _studentLocation;
  bool _windowActive = false;
  int _remainingSeconds = 0;
  Timer? _statusPollTimer;
  double? _thresholdMeters;
  bool _isGettingLocation = false;
  CountDownController _countDownController = CountDownController();
  DateTime? _windowStartTime;
  DateTime? _windowEndTime;
  String? _activeGroupId; // Store the group_id of active window for submission
  String? _sessionName; // Store the session name
  final MapController _mapController = MapController();
  bool _isMapHovered = false;
  
  // Messages state
  List<Map<String, dynamic>> _messages = [];
  bool _isLoadingMessages = false;
  Timer? _messagesRefreshTimer;
  String? _lastMessageId; // Track last message ID to detect new messages
  Map<String, dynamic>? _newMessageNotification; // Store new message for notification
  bool _showMessageNotification = false;
  int _unreadMessageCount = 0; // Track unread message count

  @override
  void initState() {
    super.initState();
    _startPolling();
    _fetchMessages();
    
    // Auto-refresh messages every 10 seconds
    _messagesRefreshTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (mounted) {
        _fetchMessages(showLoading: false);
      } else {
        timer.cancel();
      }
    });
  }

  @override
  void dispose() {
    _statusPollTimer?.cancel();
    _messagesRefreshTimer?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  void _navigateToMessages() {
    // Reset unread count when user opens messages
    setState(() {
      _unreadMessageCount = 0;
    });
    // Navigate directly to messages page
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => StudentMessagesPage(
          studentId: widget.studentId,
        ),
      ),
    );
  }
  
  Future<void> _fetchMessages({bool showLoading = true}) async {
    if (showLoading && mounted) {
      setState(() {
        _isLoadingMessages = true;
      });
    }

    try {
      final url = ApiConfig.getMessages(widget.studentId);
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200 && response.body.isNotEmpty) {
        try {
          final data = json.decode(response.body);
          if (mounted) {
            final newMessages = List<Map<String, dynamic>>.from(data['messages'] ?? []);
            
            // Check for new messages (works for both group messages and "send to all" messages)
            bool newMessageDetected = false;
            if (newMessages.isNotEmpty) {
              final latestMessage = newMessages.first;
              final latestMessageId = latestMessage['id']?.toString();
              
              if (latestMessageId != null) {
                // If we have a new message that we haven't seen before
                if (_lastMessageId != null && latestMessageId != _lastMessageId) {
                  // New message detected - show notification immediately
                  // This works for both group-specific and "send to all" messages
                  print('📬 New message detected via polling: $latestMessageId');
                  print('📬 Previous message ID: $_lastMessageId');
                  print('📬 Message title: ${latestMessage['title']}');
                  print('📬 Current notification state: $_showMessageNotification');
                  newMessageDetected = true;
                  if (mounted) {
                    // Always show notification for new messages (group or all students)
                    setState(() {
                      _newMessageNotification = {
                        'title': latestMessage['title'] ?? 'New Message',
                        'message': latestMessage['message'] ?? '',
                        'id': latestMessageId,
                      };
                      _showMessageNotification = true;
                      _lastMessageId = latestMessageId;
                    });
                    print('✅ Notification state set to true for message: $latestMessageId');
                  }
                } else if (_lastMessageId == null) {
                  // First time loading - set the last message ID without showing notification
                  _lastMessageId = latestMessageId;
                  print('ℹ️ First load - set last message ID: $latestMessageId');
                } else if (latestMessageId == _lastMessageId) {
                  // Same message - no new message
                  print('ℹ️ No new message - same ID: $latestMessageId');
                }
              }
            } else {
              print('ℹ️ No messages found in response');
            }
            
            // Calculate unread message count from all messages
            final unreadCount = newMessages.where((msg) => msg['is_read'] != true).length;
            
            setState(() {
              _messages = newMessages;
              _isLoadingMessages = false;
              // Update unread count - if new message was detected, it will be included in the count
              _unreadMessageCount = unreadCount;
            });
          }
        } catch (e) {
          if (mounted && showLoading) {
            setState(() {
              _messages = [];
              _isLoadingMessages = false;
            });
          }
        }
      } else {
        if (mounted && showLoading) {
          setState(() {
            _isLoadingMessages = false;
          });
        }
      }
    } catch (e) {
      if (mounted && showLoading) {
        setState(() {
          _isLoadingMessages = false;
        });
      }
    }
  }

  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  Future<void> _fetchAdminLocation() async {
    try {
      final response = await http.get(Uri.parse(ApiConfig.getAdminLocation));
      
      // Check if response body is empty
      if (response.body.isEmpty) {
        return; // Silent fail
      }
      
      if (response.statusCode == 200) {
        try {
          final data = json.decode(response.body);
          if (mounted) {
            final lat = (data['lat'] as num).toDouble();
            final lon = (data['lon'] as num).toDouble();
            
            // Only update if we got valid coordinates
            if (lat != 0 && lon != 0) {
              setState(() {
                _adminLocation = LatLng(lat, lon);
                _thresholdMeters = (data['threshold'] as num).toDouble();
              });
            } else {
              setState(() {
                _adminLocation = null;
              });
            }
          }
        } catch (e) {
          print('JSON decode error: $e');
          // Silent fail
        }
      } else if (response.statusCode == 404) {
        // Admin location not set yet - this is expected, don't show error
        if (mounted) {
          setState(() {
            _adminLocation = null;
          });
        }
      }
    } catch (e) {
      // Connection error - silent fail, keep existing state
      print('Error fetching admin location: $e');
    }
  }

  Future<void> _fetchWindowStatus() async {
    try {
      // Include student_id so backend can find relevant active windows
      final response = await http.get(
        Uri.parse('${ApiConfig.getWindowStatus}?student_id=${widget.studentId}'),
      );
      
      // Check if response body is empty
      if (response.body.isEmpty) {
        return; // Silent fail
      }
      
      if (response.statusCode == 200) {
        try {
          final data = json.decode(response.body);
          if (mounted) {
            setState(() {
              final wasActive = _windowActive;
              _windowActive = data['active'] ?? false;
              final newRemainingSeconds = data['remaining_seconds'] ?? 0;
              _activeGroupId = data['group_id'] as String?; // Store group_id for submission
              _sessionName = data['session_name'] as String?; // Store session name
              
              // Control the circular countdown timer
              if (_windowActive && newRemainingSeconds > 0) {
                // Calculate window times
                _windowEndTime = DateTime.now().add(Duration(seconds: newRemainingSeconds));
                if (!wasActive || _windowStartTime == null) {
                  _windowStartTime = DateTime.now().subtract(Duration(seconds: (600 - newRemainingSeconds).toInt()));
                }
                // If window just became active or duration changed significantly, restart
                if (!wasActive || (_remainingSeconds - newRemainingSeconds).abs() > 5) {
                  _remainingSeconds = newRemainingSeconds;
                  _countDownController.restart(duration: _remainingSeconds);
                  // Start the timer if it's not already running
                  Future.delayed(const Duration(milliseconds: 100), () {
                    if (mounted && _windowActive) {
                      try {
                        _countDownController.start();
                      } catch (e) {
                        debugPrint('Error starting countdown: $e');
                      }
                    }
                  });
                } else {
                  _remainingSeconds = newRemainingSeconds;
                }
              } else {
                _remainingSeconds = newRemainingSeconds;
                _countDownController.pause();
                _windowStartTime = null;
                _windowEndTime = null;
              }
            });
          }
        } catch (e) {
          print('JSON decode error: $e');
          // Silent fail
        }
      }
    } catch (e) {
      print('Error fetching window status: $e');
      // Silent fail - keep existing state
    }
  }
  
  Future<void> _refreshStatus() async {
    await Future.wait([
      _fetchAdminLocation(),
      _fetchWindowStatus(),
      _getStudentLocation(), // Also refresh student location
    ]);
  }

  void _startPolling() {
    // Immediate fetch on start
    _fetchWindowStatus();
    _fetchAdminLocation();
    _getStudentLocation(); // Get student location once
    
    // Poll every 2 seconds for real-time updates
    _statusPollTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (mounted) {
        _fetchWindowStatus();
        _fetchAdminLocation(); // Always fetch admin location if available
        // Update student location every 10 seconds (not too frequently to save battery)
        if (timer.tick % 5 == 0) {
          _getStudentLocation();
        }
      }
    });
  }

  Future<void> _getStudentLocation() async {
    if (_isGettingLocation) return; // Prevent multiple simultaneous requests
    
    setState(() {
      _isGettingLocation = true;
    });

    try {
      await _requestLocationPermission();
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      if (mounted) {
        setState(() {
          _studentLocation = LatLng(position.latitude, position.longitude);
          _isGettingLocation = false;
        });
      }
    } catch (e) {
      print('Error getting student location: $e');
      if (mounted) {
        setState(() {
          _isGettingLocation = false;
          // Don't clear existing location on error
        });
      }
    }
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
      throw Exception('Location permission denied');
    }
  }

  Future<void> _submitAttendance() async {
    // Show confirmation dialog first
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Submit Attendance?'),
        content: const Text(
          'Are you sure you want to submit your attendance? Make sure you are at the venue location.',
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green[600],
              foregroundColor: Colors.white,
            ),
            child: const Text('Submit'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return; // User cancelled
    }

    HapticFeedback.mediumImpact();

    setState(() {
      _isSubmitting = true;
    });

    // Show loading dialog
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            children: [
              CustomLoader(
                size: 32,
                color: Color(0xFF2196F3),
                shadowColor: Color(0x802196F3),
              ),
              SizedBox(width: 20),
              Text('Getting your location...'),
            ],
          ),
        ),
      );
    }

    try {
      // Request permission
      await _requestLocationPermission();

      // Get current location
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      // Dismiss loading dialog
      if (mounted) {
        Navigator.pop(context);
      }

      // Submit to backend
      final bodyMap = <String, String>{
        'student_name': widget.studentName,
        'student_id': widget.studentId,
        'lat': position.latitude.toString(),
        'lon': position.longitude.toString(),
        'accuracy': position.accuracy.toStringAsFixed(0),
      };
      
      // Add group_id if we have an active window with a group
      if (_activeGroupId != null) {
        bodyMap['group_id'] = _activeGroupId!;
      }
      
      final response = await http.post(
        Uri.parse(ApiConfig.submitAttendance),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: bodyMap,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _submissionStatus = 'submitted';
          _attendanceResult = {
            'status': data['status'],
            'distance': data['distance'],
            'timestamp': data['timestamp'],
          };
        });

        // Show result dialog
        if (mounted) {
          _showResultDialog(data);
        }
      } else if (response.statusCode == 403) {
        // Window closed
        if (mounted) {
          _showErrorDialog('Attendance window is closed');
        }
      } else if (response.statusCode == 409) {
        // Already submitted
        if (mounted) {
          _showInfoDialog('You have already submitted your attendance');
        }
      } else {
        final data = json.decode(response.body);
        if (mounted) {
          _showErrorDialog(data['error'] ?? 'Failed to submit attendance');
        }
      }
    } catch (e) {
      // Dismiss loading dialog if still showing
      if (mounted) {
        Navigator.pop(context);
      }

      if (mounted) {
        _showErrorDialog('Error: ${e.toString()}');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  void _showResultDialog(Map<String, dynamic> data) {
    final status = data['status'] as String;
    final distance = data['distance'] as String;
    final timestamp = data['timestamp'] as String;

    // Show tick animation dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _TickAnimationDialog(
        status: status,
        distance: distance,
        timestamp: timestamp,
      ),
    );
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.error, color: Color(0xFFF44336)),
            SizedBox(width: 12),
            Text('Error'),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showInfoDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.info, color: Color(0xFF2196F3)),
            SizedBox(width: 12),
            Text('Information'),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    
    return Stack(
      children: [
        Scaffold(
          backgroundColor: theme.scaffoldBackgroundColor,
          appBar: AppBar(
            title: Text(
              'Student Attendance',
              style: TextStyle(
                color: theme.colorScheme.onSurface,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            backgroundColor: theme.appBarTheme.backgroundColor ?? theme.scaffoldBackgroundColor,
            elevation: 0,
            iconTheme: IconThemeData(color: theme.colorScheme.onSurface),
            actions: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  IconButton(
                    icon: Icon(Icons.message, color: theme.colorScheme.onSurface),
                    onPressed: () {
                      _navigateToMessages();
                    },
                    tooltip: 'Messages',
                  ),
                  // Badge showing unread message count - also clickable
                  if (_unreadMessageCount > 0)
                    Positioned(
                      right: 8,
                      top: 8,
                      child: GestureDetector(
                        onTap: () {
                          _navigateToMessages();
                        },
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: theme.scaffoldBackgroundColor,
                              width: 2,
                            ),
                          ),
                          constraints: const BoxConstraints(
                            minWidth: 20,
                            minHeight: 20,
                          ),
                          child: Center(
                            child: Text(
                              _unreadMessageCount > 99 ? '99+' : '$_unreadMessageCount',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              Consumer<ThemeProvider>(
                builder: (context, themeProvider, _) {
                  return IconButton(
                    icon: Icon(
                      themeProvider.isDarkMode ? Icons.light_mode : Icons.dark_mode,
                      color: theme.colorScheme.onSurface,
                    ),
                    onPressed: () {
                      themeProvider.toggleTheme();
                    },
                    tooltip: themeProvider.isDarkMode ? 'Light Mode' : 'Dark Mode',
                  );
                },
              ),
              IconButton(
                icon: Icon(Icons.refresh, color: theme.colorScheme.onSurface),
                onPressed: _refreshStatus,
                tooltip: 'Refresh Status',
              ),
              IconButton(
                icon: Icon(Icons.logout, color: theme.colorScheme.onSurface),
                onPressed: _handleLogout,
                tooltip: 'Logout',
              ),
            ],
          ),
          body: Consumer<ThemeProvider>(
            builder: (context, themeProvider, _) {
              final theme = Theme.of(context);
              return SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Welcome Section - Redesigned Profile Card
                    Card(
                      elevation: 6,
                      shadowColor: theme.shadowColor.withOpacity(0.15),
                      color: theme.cardColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20.0),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              theme.cardColor,
                              theme.cardColor.withOpacity(0.95),
                            ],
                          ),
                        ),
                        child: Row(
                          children: [
                            // Circular gradient icon container
                            StatefulBuilder(
                              builder: (context, setState) {
                                bool isHovered = false;
                                return MouseRegion(
                                  onEnter: (_) {
                                    setState(() => isHovered = true);
                                  },
                                  onExit: (_) {
                                    setState(() => isHovered = false);
                                  },
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 300),
                                    width: 64,
                                    height: 64,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: (isHovered 
                                            ? const Color(0xFFC9A9E9) 
                                            : const Color(0xFFF9C97C)).withOpacity(0.4),
                                          blurRadius: 12,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                      gradient: LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: isHovered
                                            ? [const Color(0xFFC9A9E9), const Color(0xFF7EE7FC)]
                                            : [const Color(0xFFF9C97C), const Color(0xFFA2E9C1)],
                                      ),
                                    ),
                                    child: Transform.scale(
                                      scale: isHovered ? 1.1 : 1.0,
                                      child: Icon(
                                        Icons.person,
                                        color: theme.colorScheme.onSurface,
                                        size: 32,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                            // Vertical divider
                            Container(
                              width: 1,
                              height: 70,
                              margin: const EdgeInsets.symmetric(horizontal: 16),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    theme.dividerColor.withOpacity(0.0),
                                    theme.dividerColor,
                                    theme.dividerColor.withOpacity(0.0),
                                  ],
                                ),
                              ),
                            ),
                            // Student info section
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Student Name
                                  Text(
                                    widget.studentName,
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: theme.colorScheme.onSurface.withOpacity(0.8),
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  // Student ID with gradient effect
                                  ShaderMask(
                                    shaderCallback: (bounds) => LinearGradient(
                                      begin: Alignment.centerLeft,
                                      end: Alignment.centerRight,
                                      colors: isDarkMode
                                          ? [const Color(0xFF64B5F6), const Color(0xFF90CAF9)]
                                          : [const Color(0xFF005BC4), const Color(0xFF27272A)],
                                    ).createShader(bounds),
                                    child: Text(
                                      'ID: ${widget.studentId}',
                                      style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                  // Session Name (if available)
                                  if (_sessionName != null && _sessionName!.isNotEmpty) ...[
                                    const SizedBox(height: 10),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.primary.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: theme.colorScheme.primary.withOpacity(0.3),
                                          width: 1,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.event,
                                            size: 14,
                                            color: theme.colorScheme.primary,
                                          ),
                                          const SizedBox(width: 6),
                                          Flexible(
                                            child: Text(
                                              _sessionName!,
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: theme.colorScheme.primary,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Map showing admin location (show as soon as admin sets location)
                    if (_adminLocation != null) ...[
                      _buildMapCard(),
                      const SizedBox(height: 24),
                    ],

                    // Window Status and Timer (show when window is active)
                    if (_windowActive) ...[
                      Card(
                        elevation: 4,
                        shadowColor: Colors.orange.withOpacity(0.2),
                        color: theme.cardColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Container(
                          padding: const EdgeInsets.all(24.0),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Colors.orange[50]!.withOpacity(0.3),
                                Colors.orange[100]!.withOpacity(0.1),
                                theme.cardColor,
                              ],
                            ),
                            border: Border.all(
                              color: Colors.orange.withOpacity(0.2),
                              width: 1.5,
                            ),
                          ),
                          child: Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                decoration: BoxDecoration(
                                  color: Colors.orange[100]!.withOpacity(0.5),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.orange.withOpacity(0.3),
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.timer, color: Colors.orange[700], size: 24),
                                    const SizedBox(width: 10),
                                    Flexible(
                                      child: Text(
                                        'ATTENDANCE WINDOW ACTIVE',
                                        style: TextStyle(
                                          fontSize: 17,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.orange[900],
                                          letterSpacing: 0.8,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 28),
                    CircularCountDownTimer(
                      duration: _remainingSeconds > 0 ? _remainingSeconds : 600,
                      initialDuration: 0,
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
                      onStart: () {
                        debugPrint('Countdown Started');
                      },
                      onComplete: () {
                        debugPrint('Countdown Ended');
                      },
                      onChange: (String timeStamp) {
                        debugPrint('Countdown Changed $timeStamp');
                      },
                      timeFormatterFunction: (defaultFormatterFunction, duration) {
                        if (duration.inSeconds == 0) {
                          return "00:00";
                        } else {
                          return Function.apply(defaultFormatterFunction, [duration]);
                        }
                      },
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
                      ),
                      const SizedBox(height: 24),
                    ],
                    // Show waiting message only if admin location is not set
                    if (_adminLocation == null) ...[
                      Card(
                        color: theme.cardColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.schedule, color: theme.colorScheme.primary, size: 20),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  'Waiting for admin to set location...',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: theme.colorScheme.onSurface.withOpacity(0.7),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                    // Admin location is set but window not started
                    if (!_windowActive && _adminLocation != null) ...[
                      Card(
                        color: theme.cardColor,
                child: const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.schedule, color: Color(0xFF757575), size: 20),
                      SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Waiting for admin to set location...',
                          style: TextStyle(
                            fontSize: 13,
                            color: Color(0xFF757575),
                          ),
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                    // Admin location is set but window not started
                    if (!_windowActive && _adminLocation != null) ...[
                      Card(
                        color: theme.cardColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.info_outline, color: theme.colorScheme.primary, size: 20),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  'Admin location set. Waiting for attendance window to open...',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: theme.colorScheme.primary,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],

                    // Submit Button Section
                    if (_submissionStatus != 'submitted') ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: theme.colorScheme.primary.withOpacity(0.1),
                            width: 1,
                          ),
                        ),
                        child: Column(
                          children: [
                            Text(
                              'Ready to mark attendance?',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.onSurface,
                                letterSpacing: 0.3,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Make sure you are at the venue before submitting.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                color: theme.colorScheme.onSurface.withOpacity(0.7),
                              ),
                            ),
                            const SizedBox(height: 24),
                            SizedBox(
                              width: double.infinity,
                              height: 58,
                              child: ElevatedButton.icon(
                                onPressed: _isSubmitting ? null : _submitAttendance,
                                icon: _isSubmitting
                                    ? const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CustomLoaderSmall(color: Colors.white),
                                      )
                                    : const Icon(Icons.check_circle, size: 24),
                                label: Text(
                                  _isSubmitting ? 'SUBMITTING...' : 'SUBMIT ATTENDANCE',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF4CAF50),
                                  foregroundColor: Colors.white,
                                  elevation: 4,
                                  shadowColor: const Color(0xFF4CAF50).withOpacity(0.4),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                            ] else if (_attendanceResult != null) ...[
                      Card(
                        elevation: 6,
                        shadowColor: (_attendanceResult!['status'] == 'Present'
                            ? Colors.green
                            : Colors.red).withOpacity(0.3),
                        color: _attendanceResult!['status'] == 'Present'
                            ? const Color(0xFFE8F5E9)
                            : const Color(0xFFFFEBEE),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Container(
                          padding: const EdgeInsets.all(28.0),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: _attendanceResult!['status'] == 'Present'
                                  ? [
                                      const Color(0xFFE8F5E9),
                                      const Color(0xFFC8E6C9),
                                    ]
                                  : [
                                      const Color(0xFFFFEBEE),
                                      const Color(0xFFFFCDD2),
                                    ],
                            ),
                            border: Border.all(
                              color: (_attendanceResult!['status'] == 'Present'
                                  ? Colors.green
                                  : Colors.red).withOpacity(0.3),
                              width: 2,
                            ),
                          ),
                          child: Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: (_attendanceResult!['status'] == 'Present'
                                      ? Colors.green
                                      : Colors.red).withOpacity(0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  _attendanceResult!['status'] == 'Present'
                                      ? Icons.check_circle
                                      : Icons.cancel,
                                  color: _attendanceResult!['status'] == 'Present'
                                      ? const Color(0xFF4CAF50)
                                      : const Color(0xFFF44336),
                                  size: 52,
                                ),
                              ),
                              const SizedBox(height: 20),
                              Text(
                                'ATTENDANCE SUBMITTED',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: _attendanceResult!['status'] == 'Present'
                                      ? const Color(0xFF4CAF50)
                                      : const Color(0xFFF44336),
                                  letterSpacing: 0.8,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 20),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surface,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: (_attendanceResult!['status'] == 'Present'
                                        ? Colors.green
                                        : Colors.red).withOpacity(0.2),
                                  ),
                                ),
                                child: Text(
                                  'Status: ${_attendanceResult!['status']}',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                              ),
                      const SizedBox(height: 8),
                      Text(
                        'Distance: ${_attendanceResult!['distance']} meters',
                        style: const TextStyle(fontSize: 14),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Time: ${_attendanceResult!['timestamp']}',
                        style: const TextStyle(fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
            ],
                  ],
                ),
              );
            },
          ),
        ),
        // Animated Message Notification Overlay
        if (_showMessageNotification && _newMessageNotification != null)
          AnimatedMessageNotification(
            title: _newMessageNotification!['title'] ?? 'New Message',
            message: _newMessageNotification!['message'] ?? '',
            onClose: () {
              // Just close the notification - don't navigate
              // Don't reset unread count here - let it show on the badge
              setState(() {
                _showMessageNotification = false;
                _newMessageNotification = null;
              });
            },
            onTap: () {
              // onTap is handled internally by the notification widget
              // It will expand to show the message
            },
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
                    initialCenter: _studentLocation != null
                        ? LatLng(
                            (_adminLocation!.latitude + _studentLocation!.latitude) / 2,
                            (_adminLocation!.longitude + _studentLocation!.longitude) / 2,
                          )
                        : _adminLocation!,
                    initialZoom: _studentLocation != null ? 14.0 : 16.0,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.attendance.attendance_system',
                    ),
                    CircleLayer(
                      circles: [
                        if (_thresholdMeters != null && _thresholdMeters! > 0)
                          CircleMarker(
                            point: _adminLocation!,
                            radius: _thresholdMeters!,
                            color: const Color(0xFF4CAF50).withOpacity(0.15),
                            borderColor: const Color(0xFF4CAF50),
                            borderStrokeWidth: 2,
                            useRadiusInMeter: true,
                          ),
                      ],
                    ),
                    MarkerLayer(
                      markers: [
                        // Admin location marker
                        Marker(
                          point: _adminLocation!,
                          width: 40,
                          height: 40,
                          child: const Icon(
                            Icons.location_on,
                            color: Colors.blue,
                            size: 40,
                          ),
                        ),
                        // Student location marker - if available
                        if (_studentLocation != null)
                          Marker(
                            point: _studentLocation!,
                            width: 40,
                            height: 40,
                            child: const Icon(
                              Icons.person_pin_circle,
                              color: Colors.green,
                              size: 40,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              // Zoom Controls - appear on hover
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
              // Fullscreen icon - top left
              Positioned(
                left: 16,
                top: 16,
                child: AnimatedOpacity(
                  opacity: _isMapHovered ? 1.0 : 0.6,
                  duration: const Duration(milliseconds: 300),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        HapticFeedback.mediumImpact();
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => FullScreenMapPage(
                              adminLocation: _adminLocation!,
                              thresholdMeters: _thresholdMeters ?? 0,
                              mapController: _mapController,
                              studentLocation: _studentLocation,
                            ),
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.all(8.0),
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
                        child: Icon(
                          Icons.fullscreen,
                          color: Colors.blue[700],
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // Location update button - top right
              Positioned(
                right: 16,
                top: 16,
                child: AnimatedOpacity(
                  opacity: _isMapHovered ? 1.0 : 0.6,
                  duration: const Duration(milliseconds: 300),
                  child: Container(
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
                    child: IconButton(
                      icon: _isGettingLocation
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.my_location, color: Color(0xFF4CAF50)),
                      onPressed: _getStudentLocation,
                      tooltip: 'Update my location',
                    ),
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
                    child: const Icon(Icons.explore, color: Color(0xFF2196F3), size: 24),
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
                  child: const Text(
                    '--- Location Map ---',
                    style: TextStyle(
                      letterSpacing: 0.2,
                      color: Colors.grey,
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
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(50),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Icon(icon, color: Colors.blue[700], size: 20),
          ),
        ),
      ),
    );
  }
}

// Tick Animation Dialog Widget
class _TickAnimationDialog extends StatefulWidget {
  final String status;
  final String distance;
  final String timestamp;

  const _TickAnimationDialog({
    required this.status,
    required this.distance,
    required this.timestamp,
  });

  @override
  State<_TickAnimationDialog> createState() => _TickAnimationDialogState();
}

class _TickAnimationDialogState extends State<_TickAnimationDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _rotationAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _scaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.elasticOut,
      ),
    );

    _rotationAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOut,
      ),
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Transform.scale(
                scale: _scaleAnimation.value,
                child: Transform.rotate(
                  angle: _rotationAnimation.value * 0.1,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.status == 'Present'
                          ? Colors.green[50]
                          : Colors.red[50],
                    ),
                    child: Icon(
                      widget.status == 'Present'
                          ? Icons.check_circle
                          : Icons.cancel,
                      color: widget.status == 'Present'
                          ? Colors.green[600]
                          : Colors.red[600],
                      size: 60,
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 24),
          Text(
            widget.status == 'Present' ? 'Marked Present!' : 'Marked Absent',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          if (widget.status == 'Present') ...[
            Text('You were ${widget.distance} meters from venue'),
          ] else ...[
            Text('You were ${widget.distance} meters away'),
            const Text('(Required: within 100m)'),
          ],
          const SizedBox(height: 8),
          Text(
            'Submitted at: ${widget.timestamp}',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: widget.status == 'Present'
                  ? Colors.green[600]
                  : Colors.red[600],
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

