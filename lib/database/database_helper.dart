import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/task.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final path = join(await getDatabasesPath(), 'todo.db');
    return openDatabase(
      path,
      version: 4,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE tasks(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            isCompleted INTEGER NOT NULL DEFAULT 0,
            dueDate TEXT,
            priority INTEGER NOT NULL DEFAULT 1,
            tag TEXT,
            repeatType INTEGER NOT NULL DEFAULT 0
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE tasks ADD COLUMN dueDate TEXT');
        }
        if (oldVersion < 3) {
          await db.execute(
              'ALTER TABLE tasks ADD COLUMN priority INTEGER NOT NULL DEFAULT 1');
          await db.execute('ALTER TABLE tasks ADD COLUMN tag TEXT');
        }
        if (oldVersion < 4) {
          await db.execute(
              'ALTER TABLE tasks ADD COLUMN repeatType INTEGER NOT NULL DEFAULT 0');
        }
      },
    );
  }

  Future<int> insertTask(Task task) async {
    final db = await database;
    return db.insert('tasks', task.toMap());
  }

  Future<List<Task>> getTasks() async {
    final db = await database;
    final maps = await db.query('tasks', orderBy: 'id DESC');
    return maps.map((m) => Task.fromMap(m)).toList();
  }

  Future<int> updateTask(Task task) async {
    final db = await database;
    return db.update('tasks', task.toMap(),
        where: 'id = ?', whereArgs: [task.id]);
  }

  Future<int> deleteTask(int id) async {
    final db = await database;
    return db.delete('tasks', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<String>> getDistinctTags() async {
    final db = await database;
    final result = await db.rawQuery(
        "SELECT DISTINCT tag FROM tasks WHERE tag IS NOT NULL AND tag != ''");
    return result.map((row) => row['tag'] as String).toList();
  }

  Future<Map<String, int>> getPriorityBreakdown() async {
    final db = await database;
    final result = await db.rawQuery(
        'SELECT priority, COUNT(*) as count FROM tasks GROUP BY priority');
    final map = <String, int>{'low': 0, 'medium': 0, 'high': 0};
    for (final row in result) {
      final p = TaskPriority.values[row['priority'] as int];
      map[p.name] = row['count'] as int;
    }
    return map;
  }

  Future<List<int>> getCompletedPerLast7Days() async {
    final db = await database;
    final tasks = await db.query('tasks', where: 'isCompleted = 1');
    final now = DateTime.now();
    final counts = List<int>.filled(7, 0);
    for (final t in tasks) {
      final dueStr = t['dueDate'] as String?;
      if (dueStr == null) {
        counts[6]++;
        continue;
      }
      final due = DateTime.parse(dueStr);
      final daysAgo = now.difference(due).inDays;
      final idx = 6 - daysAgo;
      if (idx >= 0 && idx < 7) counts[idx]++;
      else counts[6]++;
    }
    return counts;
  }

  Future<void> replaceAllTasks(List<Task> tasks) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('tasks');
      for (final t in tasks) {
        t.id = null;
        await txn.insert('tasks', t.toMap());
      }
    });
  }
}