import 'package:flutter/material.dart';

enum TaskPriority { low, medium, high }

enum RepeatType { none, daily, weekly, monthly }

class Task {
  int? id;
  String title;
  bool isCompleted;
  DateTime? dueDate;
  TaskPriority priority;
  String? tag;
  RepeatType repeat;

  Task({
    this.id,
    required this.title,
    this.isCompleted = false,
    this.dueDate,
    this.priority = TaskPriority.medium,
    this.tag,
    this.repeat = RepeatType.none,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'isCompleted': isCompleted ? 1 : 0,
      'dueDate': dueDate?.toIso8601String(),
      'priority': priority.index,
      'tag': tag,
      'repeatType': repeat.index,
    };
  }

  factory Task.fromMap(Map<String, dynamic> map) {
    return Task(
      id: map['id'],
      title: map['title'],
      isCompleted: map['isCompleted'] == 1,
      dueDate: map['dueDate'] != null
          ? DateTime.parse(map['dueDate'] as String)
          : null,
      priority: TaskPriority.values[map['priority'] ?? 1],
      tag: map['tag'],
      repeat: RepeatType.values[map['repeatType'] ?? 0],
    );
  }

  Color get priorityColor {
    switch (priority) {
      case TaskPriority.high:
        return const Color(0xFFEF4444);
      case TaskPriority.medium:
        return const Color(0xFFF59E0B);
      case TaskPriority.low:
        return const Color(0xFF10B981);
    }
  }

  String get priorityLabel {
    switch (priority) {
      case TaskPriority.high:
        return 'High';
      case TaskPriority.medium:
        return 'Medium';
      case TaskPriority.low:
        return 'Low';
    }
  }

  String get repeatLabel {
    switch (repeat) {
      case RepeatType.none:
        return '';
      case RepeatType.daily:
        return 'Daily';
      case RepeatType.weekly:
        return 'Weekly';
      case RepeatType.monthly:
        return 'Monthly';
    }
  }

  /// Advance a date by the repeat interval
  DateTime? advanceDueDate(DateTime? from) {
    final base = from ?? DateTime.now();
    switch (repeat) {
      case RepeatType.none:
        return null;
      case RepeatType.daily:
        return base.add(const Duration(days: 1));
      case RepeatType.weekly:
        return base.add(const Duration(days: 7));
      case RepeatType.monthly:
        // Same day next month, clamped for short months
        final targetMonth = base.month + 1;
        final year = base.year + (targetMonth > 12 ? 1 : 0);
        final month = targetMonth > 12 ? 1 : targetMonth;
        final lastDay = DateTime(year, month + 1, 0).day;
        final day = base.day > lastDay ? lastDay : base.day;
        return DateTime(year, month, day, base.hour, base.minute);
    }
  }
}