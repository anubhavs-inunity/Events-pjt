class Student {
  final String id;
  final String name;
  final String status;
  final double? distance;

  Student({
    required this.id,
    required this.name,
    required this.status,
    this.distance,
  });

  factory Student.fromJson(Map<String, dynamic> json) {
    // Optimized: Support both old format (for backward compatibility) and new simplified format
    // For group creation, we need student_id (string like "ST001"), not UUID
    // Priority: student_id > studentID > StudentID > id (UUID)
    return Student(
      id: json['student_id'] ?? json['studentID'] ?? json['StudentID'] ?? json['id'] ?? 'N/A',
      name: json['student_name'] ?? json['StudentName'] ?? json['studentName'] ?? json['student_name'] ?? 'N/A',
      status: json['status'] ?? json['Status'] ?? 'Unknown',
      distance: json['distance'] != null
          ? (json['distance'] is num ? json['distance'].toDouble() : double.tryParse(json['distance'].toString()))
          : json['Distance'] != null
              ? (json['Distance'] is num ? json['Distance'].toDouble() : double.tryParse(json['Distance'].toString()))
              : null,
    );
  }

  bool get isPresent => status.toLowerCase() == 'present';
}

