import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:convert';
import 'dart:async';
import '../config/api_config.dart';
import '../widgets/custom_loader.dart';

class StudentLocation {
  final String studentID;
  final String studentName;
  final double latitude;
  final double longitude;
  final double distance;
  final String timestamp;
  final String status;

  StudentLocation({
    required this.studentID,
    required this.studentName,
    required this.latitude,
    required this.longitude,
    required this.distance,
    required this.timestamp,
    required this.status,
  });

  factory StudentLocation.fromJson(Map<String, dynamic> json) {
    // Try both capitalized and lowercase field names
    final studentID = json['StudentID'] ?? json['studentID'] ?? json['student_id'] ?? '';
    final studentName = json['StudentName'] ?? json['studentName'] ?? json['student_name'] ?? '';
    final lat = json['Latitude'] ?? json['latitude'] ?? 0.0;
    final lon = json['Longitude'] ?? json['longitude'] ?? 0.0;
    final dist = json['Distance'] ?? json['distance'] ?? 0.0;
    final timestamp = json['Timestamp'] ?? json['timestamp'] ?? '';
    final status = json['Status'] ?? json['status'] ?? '';
    
    return StudentLocation(
      studentID: studentID,
      studentName: studentName,
      latitude: (lat as num).toDouble(),
      longitude: (lon as num).toDouble(),
      distance: (dist as num).toDouble(),
      timestamp: timestamp.toString(),
      status: status.toString(),
    );
  }
}

class ViewStudentLocationsPage extends StatefulWidget {
  final LatLng adminLocation;
  final double thresholdMeters;
  final String? groupId; // Add group_id support

  const ViewStudentLocationsPage({
    super.key,
    required this.adminLocation,
    required this.thresholdMeters,
    this.groupId,
  });

  @override
  State<ViewStudentLocationsPage> createState() => _ViewStudentLocationsPageState();
}

class _ViewStudentLocationsPageState extends State<ViewStudentLocationsPage> {
  List<StudentLocation> _students = [];
  bool _isLoading = false;
  String? _selectedStudentID;
  bool _viewAll = false;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _fetchStudentLocations(showLoading: true);
    // Auto-refresh every 3 seconds (silent background refresh)
    _refreshTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (mounted) {
        _fetchStudentLocations(showLoading: false); // Silent refresh
      } else {
        timer.cancel();
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchStudentLocations({bool showLoading = false}) async {
    // Only show loading indicator for manual refreshes
    if (showLoading && mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      // Build URL with group_id if available
      String url = ApiConfig.getAllStudentLocations;
      if (widget.groupId != null) {
        url = '$url?group_id=${widget.groupId}';
      }
      
      final response = await http.get(Uri.parse(url));
      
      if (response.statusCode == 200 && response.body.isNotEmpty) {
        final data = json.decode(response.body);
        
        if (mounted) {
          List<StudentLocation> newStudents = [];
          
          if (data['students'] != null && data['students'] is List) {
            newStudents = (data['students'] as List)
                .map((json) => StudentLocation.fromJson(json))
                .toList();
          }
          
          // Only update state if data actually changed to avoid unnecessary rebuilds
          bool dataChanged = newStudents.length != _students.length ||
              !_areListsEqual(newStudents, _students);
          
          if (dataChanged || showLoading) {
            setState(() {
              _students = newStudents;
              _isLoading = false;
            });
          } else if (showLoading) {
            // If no change but we showed loading, hide it
            setState(() {
              _isLoading = false;
            });
          }
        }
      } else {
        // Only update state on error if it was a manual refresh
        if (showLoading && mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      // Only update state on error if it was a manual refresh
      if (showLoading && mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // Helper function to compare two lists of StudentLocation
  // Returns true if lists contain the same students with same data (order-independent)
  bool _areListsEqual(List<StudentLocation> list1, List<StudentLocation> list2) {
    if (list1.length != list2.length) return false;
    
    // Create maps for efficient lookup
    final map1 = <String, StudentLocation>{};
    final map2 = <String, StudentLocation>{};
    
    for (var student in list1) {
      map1[student.studentID] = student;
    }
    
    for (var student in list2) {
      map2[student.studentID] = student;
    }
    
    // Check if all students in list1 exist in list2 with same data
    for (var student in list1) {
      final other = map2[student.studentID];
      if (other == null) return false;
      
      // Compare relevant fields (ignore timestamp as it might change)
      if ((student.latitude - other.latitude).abs() > 0.000001 ||
          (student.longitude - other.longitude).abs() > 0.000001 ||
          student.status != other.status) {
        return false;
      }
    }
    
    return true;
  }

  LatLng _getMapCenter() {
    if (_viewAll && _students.isNotEmpty) {
      // Center between admin and all students
      double avgLat = widget.adminLocation.latitude;
      double avgLon = widget.adminLocation.longitude;
      
      for (var student in _students) {
        avgLat += student.latitude;
        avgLon += student.longitude;
      }
      avgLat /= (_students.length + 1);
      avgLon /= (_students.length + 1);
      
      return LatLng(avgLat, avgLon);
    } else if (_selectedStudentID != null) {
      final student = _students.firstWhere((s) => s.studentID == _selectedStudentID);
      // Center between admin and selected student
      return LatLng(
        (widget.adminLocation.latitude + student.latitude) / 2,
        (widget.adminLocation.longitude + student.longitude) / 2,
      );
    }
    return widget.adminLocation;
  }

  double _getMapZoom() {
    if (_viewAll && _students.isNotEmpty) {
      return 13.0; // Zoom out to show all
    } else if (_selectedStudentID != null) {
      return 15.0; // Zoom in for individual view
    }
    return 16.0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text(
          '📍 Student Locations',
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: const Color(0xFF9C27B0),
        elevation: 4,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child:           IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: () => _fetchStudentLocations(showLoading: true),
            tooltip: 'Refresh',
          ),
          ),
        ],
      ),
      body: _isLoading
          ? Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFF9C27B0).withOpacity(0.1),
                    Colors.white,
                  ],
                ),
              ),
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CustomLoader(
                      size: 48,
                      color: Color(0xFF9C27B0),
                      shadowColor: Color(0x809C27B0),
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Loading student locations...',
                      style: TextStyle(
                        fontSize: 16,
                        color: Color(0xFF757575),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : _students.isEmpty
              ? Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        const Color(0xFF9C27B0).withOpacity(0.1),
                        Colors.white,
                      ],
                    ),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.grey.withOpacity(0.3),
                                blurRadius: 10,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.location_off,
                            size: 64,
                            color: Color(0xFF9C27B0),
                          ),
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'No Student Locations',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF212121),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 48.0),
                          child: Text(
                            'Students will appear here after they submit attendance during an active window',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 16,
                              color: Color(0xFF757575),
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    // Header with stats
                    Container(
                      padding: const EdgeInsets.all(20.0),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xFF9C27B0),
                            const Color(0xFF7B1FA2),
                          ],
                        ),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Student Locations',
                                      style: TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    const Text(
                                      'Track all student positions',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.white70,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  '${_students.length}',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          // View mode toggle
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: () {
                                        setState(() {
                                          _viewAll = true;
                                          _selectedStudentID = null;
                                        });
                                      },
                                      borderRadius: BorderRadius.circular(12),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 12,
                                          horizontal: 16,
                                        ),
                                        decoration: BoxDecoration(
                                          color: _viewAll
                                              ? Colors.white
                                              : Colors.transparent,
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.map,
                                              color: _viewAll
                                                  ? const Color(0xFF9C27B0)
                                                  : Colors.white,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              'View All',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: _viewAll
                                                    ? const Color(0xFF9C27B0)
                                                    : Colors.white,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: () {
                                        setState(() {
                                          _viewAll = false;
                                          if (_selectedStudentID == null &&
                                              _students.isNotEmpty) {
                                            _selectedStudentID = _students.first.studentID;
                                          }
                                        });
                                      },
                                      borderRadius: BorderRadius.circular(12),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 12,
                                          horizontal: 16,
                                        ),
                                        decoration: BoxDecoration(
                                          color: !_viewAll
                                              ? Colors.white
                                              : Colors.transparent,
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.person,
                                              color: !_viewAll
                                                  ? const Color(0xFF9C27B0)
                                                  : Colors.white,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              'Individual',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: !_viewAll
                                                    ? const Color(0xFF9C27B0)
                                                    : Colors.white,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Map
                    Expanded(
                      flex: 2,
                      child: Container(
                        margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 10,
                              spreadRadius: 2,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: FlutterMap(
                            options: MapOptions(
                              initialCenter: _getMapCenter(),
                              initialZoom: _getMapZoom(),
                            ),
                            children: [
                              TileLayer(
                                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                userAgentPackageName: 'com.attendance.attendance_system',
                              ),
                              CircleLayer(
                                circles: [
                                  CircleMarker(
                                    point: widget.adminLocation,
                                    radius: widget.thresholdMeters,
                                    color: const Color(0xFF4CAF50).withOpacity(0.1),
                                    useRadiusInMeter: true,
                                  ),
                                ],
                              ),
                              MarkerLayer(
                                markers: [
                                  // Admin location
                                  Marker(
                                    point: widget.adminLocation,
                                    width: 100,
                                    height: 100,
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF9C27B0),
                                            shape: BoxShape.circle,
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black.withOpacity(0.3),
                                                blurRadius: 8,
                                                spreadRadius: 2,
                                              ),
                                            ],
                                          ),
                                          child: const Icon(
                                            Icons.location_on,
                                            color: Colors.white,
                                            size: 40,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF9C27B0),
                                            borderRadius: BorderRadius.circular(12),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black.withOpacity(0.2),
                                                blurRadius: 4,
                                              ),
                                            ],
                                          ),
                                          child: const Text(
                                            'Admin',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Student locations
                                  if (_viewAll)
                                    ..._students.map((student) {
                                      final isPresent = student.status == 'Present';
                                      return Marker(
                                        point: LatLng(student.latitude, student.longitude),
                                        width: 90,
                                        height: 90,
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.all(6),
                                              decoration: BoxDecoration(
                                                color: isPresent
                                                    ? const Color(0xFF4CAF50)
                                                    : const Color(0xFFF44336),
                                                shape: BoxShape.circle,
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: Colors.black.withOpacity(0.3),
                                                    blurRadius: 6,
                                                    spreadRadius: 1,
                                                  ),
                                                ],
                                              ),
                                              child: Icon(
                                                Icons.person,
                                                color: Colors.white,
                                                size: 28,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 6,
                                                vertical: 2,
                                              ),
                                              decoration: BoxDecoration(
                                                color: isPresent
                                                    ? const Color(0xFF4CAF50)
                                                    : const Color(0xFFF44336),
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: Text(
                                                student.studentName.split(' ').first,
                                                style: const TextStyle(
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    })
                                  else if (_selectedStudentID != null)
                                    Marker(
                                      point: LatLng(
                                        _students
                                            .firstWhere((s) => s.studentID == _selectedStudentID)
                                            .latitude,
                                        _students
                                            .firstWhere((s) => s.studentID == _selectedStudentID)
                                            .longitude,
                                      ),
                                      width: 110,
                                      height: 110,
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(10),
                                            decoration: BoxDecoration(
                                              color: _students
                                                          .firstWhere((s) =>
                                                              s.studentID ==
                                                              _selectedStudentID)
                                                          .status ==
                                                      'Present'
                                                  ? const Color(0xFF4CAF50)
                                                  : const Color(0xFFF44336),
                                              shape: BoxShape.circle,
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.black.withOpacity(0.4),
                                                  blurRadius: 10,
                                                  spreadRadius: 2,
                                                ),
                                              ],
                                            ),
                                            child: const Icon(
                                              Icons.person,
                                              color: Colors.white,
                                              size: 40,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: _students
                                                          .firstWhere((s) =>
                                                              s.studentID ==
                                                              _selectedStudentID)
                                                          .status ==
                                                      'Present'
                                                  ? const Color(0xFF4CAF50)
                                                  : const Color(0xFFF44336),
                                              borderRadius: BorderRadius.circular(12),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.black.withOpacity(0.2),
                                                  blurRadius: 4,
                                                ),
                                              ],
                                            ),
                                            child: Text(
                                              _students
                                                  .firstWhere((s) =>
                                                      s.studentID == _selectedStudentID)
                                                  .studentName,
                                              style: const TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // Student list
                    Expanded(
                      flex: 1,
                      child: Container(
                        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 10,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(16.0),
                              decoration: BoxDecoration(
                                color: const Color(0xFF9C27B0).withOpacity(0.1),
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(16),
                                  topRight: Radius.circular(16),
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.people,
                                    color: Color(0xFF9C27B0),
                                    size: 22,
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      _viewAll
                                          ? 'All Students (${_students.length})'
                                          : 'Select Student',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF212121),
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: _students.isEmpty
                                  ? const Center(
                                      child: Text(
                                        'No students found',
                                        style: TextStyle(
                                          color: Color(0xFF9E9E9E),
                                        ),
                                      ),
                                    )
                                  : ListView.builder(
                                      padding: const EdgeInsets.all(8),
                                      itemCount: _students.length,
                                      itemBuilder: (context, index) {
                                        final student = _students[index];
                                        final isSelected =
                                            _selectedStudentID == student.studentID;
                                        final isPresent = student.status == 'Present';

                                        return Container(
                                          margin: const EdgeInsets.only(bottom: 8),
                                          decoration: BoxDecoration(
                                            color: isSelected
                                                ? const Color(0xFF9C27B0).withOpacity(0.1)
                                                : Colors.white,
                                            borderRadius: BorderRadius.circular(12),
                                            border: Border.all(
                                              color: isSelected
                                                  ? const Color(0xFF9C27B0)
                                                  : Colors.grey.withOpacity(0.2),
                                              width: isSelected ? 2 : 1,
                                            ),
                                          ),
                                          child: ListTile(
                                            contentPadding: const EdgeInsets.symmetric(
                                              horizontal: 16,
                                              vertical: 8,
                                            ),
                                            leading: Container(
                                              padding: const EdgeInsets.all(8),
                                              decoration: BoxDecoration(
                                                color: isPresent
                                                    ? const Color(0xFF4CAF50)
                                                        .withOpacity(0.2)
                                                    : const Color(0xFFF44336)
                                                        .withOpacity(0.2),
                                                shape: BoxShape.circle,
                                              ),
                                              child: Icon(
                                                isPresent
                                                    ? Icons.check_circle
                                                    : Icons.cancel,
                                                color: isPresent
                                                    ? const Color(0xFF4CAF50)
                                                    : const Color(0xFFF44336),
                                                size: 24,
                                              ),
                                            ),
                                            title: Text(
                                              student.studentName,
                                              style: TextStyle(
                                                fontWeight: isSelected
                                                    ? FontWeight.bold
                                                    : FontWeight.w600,
                                                fontSize: 16,
                                                color: const Color(0xFF212121),
                                              ),
                                            ),
                                            subtitle: Padding(
                                              padding: const EdgeInsets.only(top: 4.0),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    children: [
                                                      const Icon(
                                                        Icons.straighten,
                                                        size: 14,
                                                        color: Color(0xFF757575),
                                                      ),
                                                      const SizedBox(width: 4),
                                                      Text(
                                                        '${student.distance.toStringAsFixed(0)}m away',
                                                        style: const TextStyle(
                                                          fontSize: 13,
                                                          color: Color(0xFF757575),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Row(
                                                    children: [
                                                      const Icon(
                                                        Icons.access_time,
                                                        size: 14,
                                                        color: Color(0xFF757575),
                                                      ),
                                                      const SizedBox(width: 4),
                                                      Text(
                                                        student.timestamp,
                                                        style: const TextStyle(
                                                          fontSize: 12,
                                                          color: Color(0xFF9E9E9E),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),
                                            trailing: Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 12,
                                                vertical: 6,
                                              ),
                                              decoration: BoxDecoration(
                                                color: isPresent
                                                    ? const Color(0xFF4CAF50)
                                                    : const Color(0xFFF44336),
                                                borderRadius: BorderRadius.circular(20),
                                              ),
                                              child: Text(
                                                student.status,
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                            onTap: () {
                                              setState(() {
                                                _viewAll = false;
                                                _selectedStudentID = student.studentID;
                                              });
                                            },
                                          ),
                                        );
                                      },
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}

