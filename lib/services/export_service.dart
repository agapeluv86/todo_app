import 'dart:convert';
import 'package:flutter/services.dart';
import '../models/task.dart';

class ExportService {
  static String exportToJson(List<Task> tasks) {
    final data = {
      'version': 2,
      'exportedAt': DateTime.now().toIso8601String(),
      'tasks': tasks.map((t) => t.toMap()).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  static Future<void> copyToClipboard(String json) async {
    await Clipboard.setData(ClipboardData(text: json));
  }

  static List<Task>? importFromJson(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final list = decoded['tasks'];
      if (list is! List) return null;
      return list
          .whereType<Map>()
          .map((m) => Task.fromMap(Map<String, dynamic>.from(m)))
          .toList();
    } catch (_) {
      return null;
    }
  }
}