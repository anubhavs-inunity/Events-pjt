import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'dart:convert';
import 'dart:async';
import '../config/api_config.dart';

class StudentMessagesPage extends StatefulWidget {
  final String studentId;

  const StudentMessagesPage({
    super.key,
    required this.studentId,
  });

  @override
  State<StudentMessagesPage> createState() => _StudentMessagesPageState();
}

class _StudentMessagesPageState extends State<StudentMessagesPage> {
  List<Map<String, dynamic>> _messages = [];
  bool _isLoading = true;
  Timer? _refreshTimer;
  bool _isSelectionMode = false;
  Set<String> _selectedMessageIds = {};

  @override
  void initState() {
    super.initState();
    _fetchMessages();
    // Auto-refresh every 10 seconds
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (mounted) {
        _fetchMessages(showLoading: false);
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

  Future<void> _fetchMessages({bool showLoading = true}) async {
    if (showLoading && mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      final url = ApiConfig.getMessages(widget.studentId);
      print('🔍 Fetching messages for student: ${widget.studentId}');
      print('🔍 URL: $url');
      
      final response = await http.get(Uri.parse(url));

      print('📥 Response status: ${response.statusCode}');
      print('📥 Response body length: ${response.body.length}');
      
      if (response.statusCode == 200) {
        if (response.body.isNotEmpty) {
          try {
            final data = json.decode(response.body);
            print('✅ Parsed data: ${data.toString()}');
            print('✅ Messages count: ${(data['messages'] as List?)?.length ?? 0}');
            
            if (mounted) {
              setState(() {
                _messages = List<Map<String, dynamic>>.from(data['messages'] ?? []);
                _isLoading = false;
              });
            }
          } catch (e) {
            print('❌ JSON parse error: $e');
            print('❌ Response body: ${response.body}');
            // JSON parse error - set empty messages
            if (mounted) {
              setState(() {
                _messages = [];
                _isLoading = false;
              });
            }
          }
        } else {
          print('⚠️ Empty response body');
          // Empty response - no messages
          if (mounted) {
            setState(() {
              _messages = [];
              _isLoading = false;
            });
          }
        }
      } else {
        print('❌ Error status: ${response.statusCode}');
        print('❌ Response body: ${response.body}');
        if (mounted && showLoading) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      print('❌ Exception fetching messages: $e');
      if (mounted && showLoading) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _markAsRead(String messageId) async {
    try {
      await http.post(
        Uri.parse(ApiConfig.markMessageRead),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'student_id': widget.studentId,
          'message_id': messageId,
        }),
      );
      
      // Update local state
      setState(() {
        final index = _messages.indexWhere((m) => m['id'] == messageId);
        if (index != -1) {
          _messages[index]['is_read'] = true;
        }
      });
    } catch (e) {
      // Silent fail
    }
  }

  void _toggleSelectAll() {
    setState(() {
      if (_selectedMessageIds.length == _messages.length && _messages.isNotEmpty) {
        // Deselect all
        _selectedMessageIds.clear();
      } else {
        // Select all
        _selectedMessageIds = _messages
            .where((m) => m['id'] != null)
            .map((m) => m['id'].toString())
            .toSet();
      }
    });
  }

  Future<void> _deleteSelectedMessages() async {
    if (_selectedMessageIds.isEmpty) return;

    // Show confirmation dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text('Delete Messages'),
        content: Text(
          'Are you sure you want to delete ${_selectedMessageIds.length} message(s)?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    // Delete all selected messages
    final messageIdsToDelete = List<String>.from(_selectedMessageIds);
    int successCount = 0;
    int failCount = 0;

    for (final messageId in messageIdsToDelete) {
      try {
        print('🗑️ Deleting message ID: $messageId');
        final response = await http.post(
          Uri.parse(ApiConfig.deleteMessage),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'student_id': widget.studentId,
            'message_id': messageId,
          }),
        );

        print('📥 Delete response status: ${response.statusCode}');
        print('📥 Delete response body: ${response.body}');

        if (response.statusCode == 200) {
          try {
            final responseData = json.decode(response.body);
            if (responseData['status'] == 'success' || responseData['message'] != null) {
              successCount++;
              print('✅ Successfully deleted message: $messageId');
            } else {
              print('❌ Delete response indicates failure: $responseData');
              failCount++;
            }
          } catch (e) {
            // If response is not JSON but status is 200, consider it success
            successCount++;
            print('✅ Deleted message (non-JSON response): $messageId');
          }
        } else {
          print('❌ Failed to delete message $messageId: ${response.statusCode} - ${response.body}');
          failCount++;
        }
      } catch (e) {
        print('❌ Error deleting message $messageId: $e');
        failCount++;
      }
    }

    // Clear selection
    setState(() {
      _selectedMessageIds.clear();
      _isSelectionMode = false;
    });

    // Always refresh messages from server to ensure UI is in sync with backend
    await _fetchMessages(showLoading: false);

    // Show result message
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            successCount > 0
                ? 'Deleted $successCount message(s)${failCount > 0 ? '. $failCount failed.' : ''}'
                : 'Failed to delete messages',
          ),
          backgroundColor: successCount > 0 ? Colors.green : Colors.red,
        ),
      );
    }
  }

  void _toggleMessageSelection(String messageId) {
    setState(() {
      if (_selectedMessageIds.contains(messageId)) {
        _selectedMessageIds.remove(messageId);
      } else {
        _selectedMessageIds.add(messageId);
      }
    });
  }

  Future<void> _deleteMessage(String messageId) async {
    // Show confirmation dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text('Delete Message'),
        content: const Text('Are you sure you want to delete this message?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final response = await http.post(
        Uri.parse(ApiConfig.deleteMessage),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'student_id': widget.studentId,
          'message_id': messageId,
        }),
      );

      if (response.statusCode == 200) {
        // Refresh messages from server to ensure UI is in sync
        await _fetchMessages(showLoading: false);
        
        // Show success message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Message deleted successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        print('❌ Failed to delete message: ${response.statusCode} - ${response.body}');
        throw Exception('Failed to delete message: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error deleting message: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete message: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        // Refresh messages when returning to dashboard
        if (didPop) {
          // This will trigger a refresh in the parent
        }
      },
      child: Scaffold(
      appBar: AppBar(
        title: Text(
          _isSelectionMode
              ? '${_selectedMessageIds.length} Selected'
              : '📬 Messages',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.purple[700],
        elevation: 4,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (_isSelectionMode) ...[
            // Select All / Deselect All button
            IconButton(
              icon: Icon(
                _selectedMessageIds.length == _messages.length
                    ? Icons.deselect
                    : Icons.select_all,
                color: Colors.white,
              ),
              onPressed: _toggleSelectAll,
              tooltip: _selectedMessageIds.length == _messages.length
                  ? 'Deselect All'
                  : 'Select All',
            ),
            // Delete selected button
            if (_selectedMessageIds.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.delete, color: Colors.white),
                onPressed: _deleteSelectedMessages,
                tooltip: 'Delete Selected (${_selectedMessageIds.length})',
              ),
            // Cancel selection mode
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () {
                setState(() {
                  _isSelectionMode = false;
                  _selectedMessageIds.clear();
                });
              },
              tooltip: 'Cancel',
            ),
          ] else ...[
            // Enter selection mode
            IconButton(
              icon: const Icon(Icons.checklist, color: Colors.white),
              onPressed: () {
                setState(() {
                  _isSelectionMode = true;
                });
              },
              tooltip: 'Select Messages',
            ),
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white),
              onPressed: () => _fetchMessages(),
              tooltip: 'Refresh',
            ),
          ],
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : _messages.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.inbox,
                        size: 80,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No Messages',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'You have no messages yet',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _fetchMessages,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message = _messages[index];
                      final isRead = message['is_read'] == true;
                      final createdAt = message['created_at'] as String?;
                      
                      DateTime? dateTime;
                      if (createdAt != null) {
                        try {
                          dateTime = DateTime.parse(createdAt);
                        } catch (e) {
                          // Ignore parse errors
                        }
                      }

                      final messageId = message['id'].toString();
                      final isSelected = _selectedMessageIds.contains(messageId);
                      
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        elevation: isRead ? 2 : 4,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: _isSelectionMode && isSelected
                              ? BorderSide(color: Colors.purple[700]!, width: 2)
                              : BorderSide.none,
                        ),
                        color: _isSelectionMode && isSelected
                            ? Colors.purple[50]
                            : (isRead ? Colors.white : Colors.blue[50]),
                        child: InkWell(
                          onTap: () {
                            if (_isSelectionMode) {
                              _toggleMessageSelection(messageId);
                            } else {
                              if (!isRead) {
                                _markAsRead(message['id']);
                              }
                              _showMessageDialog(message);
                            }
                          },
                          borderRadius: BorderRadius.circular(16),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    // Checkbox in selection mode
                                    if (_isSelectionMode) ...[
                                      Checkbox(
                                        value: isSelected,
                                        onChanged: (value) {
                                          _toggleMessageSelection(messageId);
                                        },
                                        activeColor: Colors.purple[700],
                                      ),
                                      const SizedBox(width: 8),
                                    ],
                                    Expanded(
                                      child: Text(
                                        message['title'] ?? 'No Title',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: isRead
                                              ? FontWeight.w600
                                              : FontWeight.bold,
                                          color: Colors.black87,
                                        ),
                                      ),
                                    ),
                                    // Delete button (only when not in selection mode)
                                    if (!_isSelectionMode) ...[
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline, size: 20),
                                        color: Colors.red[400],
                                        onPressed: () => _deleteMessage(message['id']),
                                        tooltip: 'Delete message',
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                      ),
                                      const SizedBox(width: 8),
                                    ],
                                    if (!isRead && !_isSelectionMode)
                                      Container(
                                        width: 12,
                                        height: 12,
                                        decoration: BoxDecoration(
                                          color: Colors.blue[700],
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  message['message'] ?? '',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[700],
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.person,
                                      size: 14,
                                      color: Colors.grey[600],
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'From: ${message['admin_name'] ?? 'Admin'}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                    const Spacer(),
                                    if (dateTime != null)
                                      Text(
                                        DateFormat('MMM d, h:mm a').format(dateTime),
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
                        ),
                      );
                    },
                  ),
                ),
      ),
    );
  }

  void _showMessageDialog(Map<String, dynamic> message) {
    final createdAt = message['created_at'] as String?;
    DateTime? dateTime;
    if (createdAt != null) {
      try {
        dateTime = DateTime.parse(createdAt);
      } catch (e) {
        // Ignore
      }
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(
          message['title'] ?? 'Message',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                message['message'] ?? '',
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.person, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    'From: ${message['admin_name'] ?? 'Admin'}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
              if (dateTime != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.access_time, size: 16, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(
                      DateFormat('MMM d, y • h:mm a').format(dateTime),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _deleteMessage(message['id']);
            },
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            label: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

