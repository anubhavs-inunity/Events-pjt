import 'package:flutter/material.dart';
import '../models/student.dart';

class StudentCard extends StatefulWidget {
  final Student student;

  const StudentCard({
    super.key,
    required this.student,
  });

  @override
  State<StudentCard> createState() => _StudentCardState();
}

class _StudentCardState extends State<StudentCard> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for keep alive
    
    final student = widget.student;
    final isPresent = student.isPresent;
    
    return RepaintBoundary(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: BoxDecoration(
          color: isPresent ? Colors.green[50] : Colors.red[50],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isPresent ? Colors.green[200]! : Colors.red[200]!,
          ),
        ),
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: isPresent ? Colors.green[400] : Colors.red[400],
            child: Icon(
              isPresent ? Icons.check : Icons.close,
              color: Colors.white,
              size: 20,
            ),
          ),
          title: Text(
            student.name,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('ID: ${student.id}'),
              if (student.distance != null && student.distance! > 0)
                Text('Distance: ${student.distance!.toStringAsFixed(2)}m'),
            ],
          ),
          trailing: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 6,
            ),
            decoration: BoxDecoration(
              color: isPresent ? Colors.green[400] : Colors.red[400],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              student.status,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

