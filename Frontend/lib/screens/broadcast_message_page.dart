import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../config/api_config.dart';

class BroadcastMessagePage extends StatefulWidget {
  final String adminId;
  final String? groupId;
  final String? groupName;
  final List<Map<String, dynamic>>? groups;

  const BroadcastMessagePage({
    super.key,
    required this.adminId,
    this.groupId,
    this.groupName,
    this.groups,
  });

  @override
  State<BroadcastMessagePage> createState() => _BroadcastMessagePageState();
}

class _BroadcastMessagePageState extends State<BroadcastMessagePage> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();
  bool _isSending = false;
  String? _selectedGroupId;
  bool _sendToAll = false;

  @override
  void initState() {
    super.initState();
    // Only set _selectedGroupId if it exists in the groups list
    if (widget.groupId != null && widget.groups != null) {
      final groupExists = widget.groups!.any((group) => group['id'] == widget.groupId);
      if (groupExists) {
        _selectedGroupId = widget.groupId;
      } else {
        _selectedGroupId = null;
      }
    } else {
      _selectedGroupId = null;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a title'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_messageController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a message'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (!_sendToAll && _selectedGroupId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a group or choose "Send to All Students"'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isSending = true;
    });

    try {
      final response = await http.post(
        Uri.parse(ApiConfig.sendBroadcastMessage),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'admin_id': widget.adminId,
          'group_id': _sendToAll ? null : _selectedGroupId,
          'title': _titleController.text.trim(),
          'message': _messageController.text.trim(),
          'send_to_all': _sendToAll,
        }),
      );

      if (response.statusCode == 200) {
        if (response.body.isNotEmpty) {
          try {
            final data = json.decode(response.body);
            if (mounted) {
              HapticFeedback.mediumImpact();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Message sent to ${data['sent_count'] ?? 0} students',
                    style: const TextStyle(color: Colors.white),
                  ),
                  backgroundColor: Colors.green,
                  duration: const Duration(seconds: 3),
                ),
              );
              
              // Clear form
              _titleController.clear();
              _messageController.clear();
              
              // Go back after a short delay
              Future.delayed(const Duration(milliseconds: 500), () {
                if (mounted) {
                  Navigator.pop(context);
                }
              });
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Message sent successfully'),
                  backgroundColor: Colors.green,
                ),
              );
              _titleController.clear();
              _messageController.clear();
              Future.delayed(const Duration(milliseconds: 500), () {
                if (mounted) {
                  Navigator.pop(context);
                }
              });
            }
          }
        } else {
          // Empty response but 200 status - assume success
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Message sent successfully'),
                backgroundColor: Colors.green,
              ),
            );
            _titleController.clear();
            _messageController.clear();
            Future.delayed(const Duration(milliseconds: 500), () {
              if (mounted) {
                Navigator.pop(context);
              }
            });
          }
        }
      } else {
        String errorMessage = 'Failed to send message';
        if (response.body.isNotEmpty) {
          try {
            final error = json.decode(response.body);
            errorMessage = error['error'] ?? errorMessage;
          } catch (e) {
            errorMessage = 'Server error: ${response.statusCode}';
          }
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMessage),
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
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '📢 Broadcast Message',
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.blue[700],
        elevation: 4,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.blue[50]!,
              Colors.white,
            ],
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Recipient Selection
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.people, color: Colors.blue[700], size: 24),
                          const SizedBox(width: 8),
                          const Text(
                            'Recipients',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Send to All option
                      CheckboxListTile(
                        title: const Text(
                          'Send to All Students',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: const Text('All students in the system'),
                        value: _sendToAll,
                        onChanged: (value) {
                          setState(() {
                            _sendToAll = value ?? false;
                            if (_sendToAll) {
                              _selectedGroupId = null;
                            }
                          });
                        },
                        activeColor: Colors.blue[700],
                      ),
                      if (!_sendToAll && widget.groups != null && widget.groups!.isNotEmpty) ...[
                        const Divider(),
                        const SizedBox(height: 8),
                        const Text(
                          'Or select a group:',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Builder(
                          builder: (context) {
                            // Get unique group IDs (remove duplicates)
                            final groupMap = <String, String>{};
                            for (var group in widget.groups!) {
                              final groupId = group['id'] as String?;
                              final groupName = group['name'] as String? ?? 'Unknown';
                              if (groupId != null && !groupMap.containsKey(groupId)) {
                                groupMap[groupId] = groupName;
                              }
                            }
                            
                            final validGroupIds = groupMap.keys.toList();
                            final currentValue = _selectedGroupId != null && validGroupIds.contains(_selectedGroupId)
                                ? _selectedGroupId
                                : null;
                            
                            // Update state if value was invalid
                            if (_selectedGroupId != null && !validGroupIds.contains(_selectedGroupId)) {
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (mounted) {
                                  setState(() {
                                    _selectedGroupId = null;
                                  });
                                }
                              });
                            }
                            
                            return DropdownButtonFormField<String>(
                              value: currentValue,
                              decoration: InputDecoration(
                                labelText: 'Select Group',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                prefixIcon: Icon(Icons.group, color: Colors.blue[700]),
                              ),
                              items: groupMap.entries.map((entry) {
                                return DropdownMenuItem<String>(
                                  value: entry.key,
                                  child: Text(entry.value),
                                );
                              }).toList(),
                              onChanged: (value) {
                                setState(() {
                                  _selectedGroupId = value;
                                });
                              },
                              // Add validator to ensure value is valid
                              validator: (value) {
                                if (!_sendToAll && value == null) {
                                  return 'Please select a group';
                                }
                                return null;
                              },
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              
              // Title Input
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.title, color: Colors.blue[700], size: 24),
                          const SizedBox(width: 8),
                          const Text(
                            'Title',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _titleController,
                        decoration: InputDecoration(
                          hintText: 'Enter message title',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: Colors.grey[50],
                        ),
                        maxLength: 100,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              
              // Message Input
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.message, color: Colors.blue[700], size: 24),
                          const SizedBox(width: 8),
                          const Text(
                            'Message',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _messageController,
                        decoration: InputDecoration(
                          hintText: 'Enter your message',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: Colors.grey[50],
                        ),
                        maxLines: 8,
                        maxLength: 1000,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 30),
              
              // Send Button
              ElevatedButton(
                onPressed: _isSending ? null : _sendMessage,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[700],
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 4,
                ),
                child: _isSending
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.send, color: Colors.white),
                          SizedBox(width: 8),
                          Text(
                            'Send Broadcast Message',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

