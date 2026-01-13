import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import '../config/api_config.dart';

class AttendanceHistoryPage extends StatefulWidget {
  final String studentId;
  final String studentName;

  const AttendanceHistoryPage({
    super.key,
    required this.studentId,
    required this.studentName,
  });

  @override
  State<AttendanceHistoryPage> createState() => _AttendanceHistoryPageState();
}

class _AttendanceHistoryPageState extends State<AttendanceHistoryPage> {
  List<Map<String, dynamic>> _attendanceHistory = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchAttendanceHistory();
  }

  Future<void> _fetchAttendanceHistory() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final response = await http.get(
        Uri.parse(ApiConfig.getStudentAttendanceHistory(widget.studentId)),
      );

      // Check if response body is empty
      if (response.body.isEmpty || response.body.trim().isEmpty) {
        setState(() {
          _error = 'Empty response from server';
          _isLoading = false;
        });
        return;
      }

      if (response.statusCode == 200) {
        try {
          final data = json.decode(response.body);
          setState(() {
            _attendanceHistory = List<Map<String, dynamic>>.from(
              data['attendance_history'] ?? [],
            );
            _isLoading = false;
          });
        } catch (jsonError) {
          setState(() {
            _error = 'Failed to parse response: ${jsonError.toString()}';
            _isLoading = false;
          });
        }
      } else {
        // Try to parse error message if available
        String errorMessage = 'Failed to load attendance history (Status: ${response.statusCode})';
        try {
          if (response.body.isNotEmpty) {
            final errorData = json.decode(response.body);
            if (errorData['error'] != null) {
              errorMessage = errorData['error'];
            }
          }
        } catch (_) {
          // Ignore JSON parse errors for error responses
        }
        setState(() {
          _error = errorMessage;
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance History'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchAttendanceHistory,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _fetchAttendanceHistory,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _attendanceHistory.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.history, size: 64, color: Colors.grey[400]),
                          const SizedBox(height: 16),
                          Text(
                            'No attendance records found',
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _fetchAttendanceHistory,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _attendanceHistory.length,
                        itemBuilder: (context, index) {
                          final record = _attendanceHistory[index];
                          final status = record['status'] as String? ?? 'Unknown';
                          final distance = record['distance'] as num? ?? 0;
                          final submittedAt = record['submitted_at'] as String?;
                          final groupName = record['group_name'] as String? ?? 'N/A';
                          final sessionName = record['session_name'] as String?;

                          DateTime? dateTime;
                          if (submittedAt != null) {
                            try {
                              dateTime = DateTime.parse(submittedAt);
                            } catch (e) {
                              // Ignore parse errors
                            }
                          }

                          final isPresent = status == 'Present';

                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            elevation: 2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isPresent
                                              ? Colors.green[50]
                                              : Colors.red[50],
                                          borderRadius: BorderRadius.circular(20),
                                          border: Border.all(
                                            color: isPresent
                                                ? Colors.green[300]!
                                                : Colors.red[300]!,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              isPresent
                                                  ? Icons.check_circle
                                                  : Icons.cancel,
                                              size: 16,
                                              color: isPresent
                                                  ? Colors.green[700]
                                                  : Colors.red[700],
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              status,
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: isPresent
                                                    ? Colors.green[700]
                                                    : Colors.red[700],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const Spacer(),
                                      if (dateTime != null)
                                        Text(
                                          DateFormat('MMM d, y').format(dateTime),
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  if (sessionName != null && sessionName.isNotEmpty) ...[
                                    Row(
                                      children: [
                                        Icon(Icons.event, size: 16, color: Colors.grey[600]),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            sessionName,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                  ],
                                  Row(
                                    children: [
                                      Icon(Icons.group, size: 16, color: Colors.grey[600]),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          'Group: $groupName',
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: Colors.grey[700],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Icon(Icons.straighten, size: 16, color: Colors.grey[600]),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Distance: ${distance.toStringAsFixed(0)}m',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.grey[700],
                                        ),
                                      ),
                                      const Spacer(),
                                      if (dateTime != null)
                                        Text(
                                          DateFormat('h:mm a').format(dateTime),
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}

