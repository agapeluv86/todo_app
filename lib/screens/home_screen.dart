import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/task.dart';
import '../database/database_helper.dart';
import '../services/notification_service.dart';
import '../services/export_service.dart';

enum TaskFilter { all, active, completed }

class HomeScreen extends StatefulWidget {
  final bool isDark;
  final VoidCallback onToggleTheme;

  const HomeScreen({
    super.key,
    required this.isDark,
    required this.onToggleTheme,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final NotificationService _notif = NotificationService();
  final GlobalKey<AnimatedListState> _listKey = GlobalKey<AnimatedListState>();

  List<Task> _tasks = [];
  List<String> _availableTags = [];
  TaskFilter _filter = TaskFilter.all;
  String? _filterTag;
  String _searchQuery = '';
  bool _searchOpen = false;
  TaskPriority _pendingPriority = TaskPriority.medium;
  RepeatType _pendingRepeat = RepeatType.none;
  String? _pendingTag;
  DateTime? _pendingDueDate;
  bool _isLoading = true;

  late AnimationController _counterAnim;
  int _lastRemaining = 0;

  Color get _cardColor =>
      widget.isDark ? const Color(0xFF1F2937) : Colors.white;
  Color get _textColor =>
      widget.isDark ? Colors.white : const Color(0xFF1F2937);
  Color get _subTextColor =>
      widget.isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280);

  @override
  void initState() {
    super.initState();
    _counterAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));
    _loadTasks();
  }

  @override
  void dispose() {
    _controller.dispose();
    _searchController.dispose();
    _counterAnim.dispose();
    super.dispose();
  }

  Future<void> _loadTasks() async {
    final tasks = await _dbHelper.getTasks();
    final tags = await _dbHelper.getDistinctTags();
    if (!mounted) return;
    setState(() {
      _tasks = tasks;
      _availableTags = tags;
      _isLoading = false;
    });
  }

  Future<void> _addTask() async {
    final title = _controller.text.trim();
    if (title.isEmpty) return;

    final task = Task(
      title: title,
      dueDate: _pendingDueDate,
      priority: _pendingPriority,
      tag: _pendingTag,
      repeat: _pendingRepeat,
    );
    final id = await _dbHelper.insertTask(task);

    if (task.dueDate != null) {
      await _notif.scheduleTaskReminder(
        id: id,
        title: task.title,
        dueDate: task.dueDate!,
      );
    }

    _controller.clear();
    setState(() {
      _pendingDueDate = null;
      _pendingTag = null;
      _pendingPriority = TaskPriority.medium;
      _pendingRepeat = RepeatType.none;
    });
    FocusScope.of(context).unfocus();
    await _loadTasks();
  }

  /// Toggles completion. If completing a recurring task, auto-spawns next instance.
  Future<void> _toggleTask(Task task) async {
    final wasCompleted = task.isCompleted;
    task.isCompleted = !task.isCompleted;
    await _dbHelper.updateTask(task);

    if (task.isCompleted && task.id != null) {
      await _notif.cancelReminder(task.id!);

      // Auto-spawn next instance for recurring tasks
      if (task.repeat != RepeatType.none && !wasCompleted) {
        final nextDue = task.advanceDueDate(task.dueDate);
        final next = Task(
          title: task.title,
          dueDate: nextDue,
          priority: task.priority,
          tag: task.tag,
          repeat: task.repeat,
        );
        final newId = await _dbHelper.insertTask(next);
        if (nextDue != null) {
          await _notif.scheduleTaskReminder(
            id: newId,
            title: next.title,
            dueDate: nextDue,
          );
        }
      }
    } else if (!task.isCompleted && task.dueDate != null && task.id != null) {
      // Re-schedule if uncompleted and had a due date
      await _notif.scheduleTaskReminder(
        id: task.id!,
        title: task.title,
        dueDate: task.dueDate!,
      );
    }
    await _loadTasks();
  }

  Future<void> _deleteTask(int id) async {
    await _notif.cancelReminder(id);
    await _dbHelper.deleteTask(id);
    await _loadTasks();
  }

  Future<void> _pickDueDate({Task? existingTask}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: existingTask?.dueDate ?? _pendingDueDate ?? now,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 365 * 5)),
    );
    if (picked == null) return;
    if (!mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    final combined = DateTime(
      picked.year,
      picked.month,
      picked.day,
      time?.hour ?? 9,
      time?.minute ?? 0,
    );

    if (existingTask != null) {
      existingTask.dueDate = combined;
      await _dbHelper.updateTask(existingTask);
      if (existingTask.id != null) {
        await _notif.scheduleTaskReminder(
          id: existingTask.id!,
          title: existingTask.title,
          dueDate: combined,
        );
      }
      await _loadTasks();
    } else {
      setState(() => _pendingDueDate = combined);
    }
  }

  Future<void> _editTask(Task task) async {
    final editController = TextEditingController(text: task.title);
    DateTime? newDue = task.dueDate;
    TaskPriority newPriority = task.priority;
    String? newTag = task.tag;
    RepeatType newRepeat = task.repeat;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('Edit Task'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: editController,
                  decoration: const InputDecoration(labelText: 'Title'),
                  autofocus: true,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<TaskPriority>(
                  value: newPriority,
                  decoration: const InputDecoration(labelText: 'Priority'),
                  items: TaskPriority.values.map((p) {
                    return DropdownMenuItem(
                      value: p,
                      child: Text(p.name.toUpperCase()),
                    );
                  }).toList(),
                  onChanged: (v) => setDlg(() => newPriority = v!),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<RepeatType>(
                  value: newRepeat,
                  decoration: const InputDecoration(labelText: 'Repeat'),
                  items: RepeatType.values.map((r) {
                    final label = r == RepeatType.none
                        ? 'None'
                        : r.name[0].toUpperCase() + r.name.substring(1);
                    return DropdownMenuItem(value: r, child: Text(label));
                  }).toList(),
                  onChanged: (v) => setDlg(() => newRepeat = v!),
                ),
                const SizedBox(height: 8),
                TextField(
                  decoration: const InputDecoration(
                      labelText: 'Tag (optional, e.g. Work)'),
                  controller: TextEditingController(text: newTag ?? ''),
                  onChanged: (v) =>
                      newTag = v.trim().isEmpty ? null : v.trim(),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        newDue == null
                            ? 'No due date'
                            : 'Due: ${DateFormat.yMMMd().add_jm().format(newDue!)}',
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: newDue ?? DateTime.now(),
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) setDlg(() => newDue = picked);
                      },
                      child: const Text('Pick'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final newTitle = editController.text.trim();
                if (newTitle.isEmpty) return;
                task.title = newTitle;
                task.dueDate = newDue;
                task.priority = newPriority;
                task.tag = newTag;
                task.repeat = newRepeat;
                await _dbHelper.updateTask(task);
                if (task.id != null && newDue != null) {
                  await _notif.scheduleTaskReminder(
                    id: task.id!,
                    title: newTitle,
                    dueDate: newDue!,
                  );
                }
                if (ctx.mounted) Navigator.pop(ctx);
                await _loadTasks();
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportTasks() async {
    if (_tasks.isEmpty) {
      _showSnack('No tasks to export');
      return;
    }
    final json = ExportService.exportToJson(_tasks);
    await ExportService.copyToClipboard(json);
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Backup copied!'),
        content: SingleChildScrollView(
          child: Text(json, style: const TextStyle(fontSize: 11)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _importTasks() async {
    final ctrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Import from JSON'),
        content: TextField(
          controller: ctrl,
          maxLines: 8,
          decoration: const InputDecoration(
              hintText: 'Paste JSON here...', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final raw = await Clipboard.getData('text/plain');
              if (raw?.text != null) ctrl.text = raw!.text!;
            },
            child: const Text('Paste'),
          ),
          ElevatedButton(
            onPressed: () async {
              final tasks = ExportService.importFromJson(ctrl.text);
              if (tasks == null || tasks.isEmpty) {
                _showSnack('Invalid JSON or empty task list');
                return;
              }
              await _dbHelper.replaceAllTasks(tasks);
              if (ctx.mounted) Navigator.pop(ctx);
              await _loadTasks();
              _showSnack('Imported ${tasks.length} tasks');
            },
            child: const Text('Import'),
          ),
        ],
      ),
    );
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  List<Task> get _filteredTasks {
    var list = _tasks;
    switch (_filter) {
      case TaskFilter.active:
        list = list.where((t) => !t.isCompleted).toList();
        break;
      case TaskFilter.completed:
        list = list.where((t) => t.isCompleted).toList();
        break;
      case TaskFilter.all:
        break;
    }
    if (_filterTag != null) {
      list = list.where((t) => t.tag == _filterTag).toList();
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list
          .where((t) =>
              t.title.toLowerCase().contains(q) ||
              (t.tag?.toLowerCase().contains(q) ?? false))
          .toList();
    }
    return list;
  }

  int get _remainingCount => _tasks.where((t) => !t.isCompleted).length;

  @override
  Widget build(BuildContext context) {
    if (_remainingCount != _lastRemaining) {
      _lastRemaining = _remainingCount;
      _counterAnim.forward(from: 0);
    }

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF6366F1),
        icon: const Icon(Icons.notifications_active, color: Colors.white),
        label: const Text('Test Notif',
            style: TextStyle(color: Colors.white)),
        onPressed: () async {
          await _notif.showTestNotification();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Notification sent!')),
            );
          }
        },
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
              child: Row(
                children: [
                  Expanded(
                    child: _searchOpen
                        ? TextField(
                            controller: _searchController,
                            autofocus: true,
                            onChanged: (v) =>
                                setState(() => _searchQuery = v),
                            style: TextStyle(color: _textColor),
                            decoration: InputDecoration(
                              hintText: 'Search tasks...',
                              hintStyle: TextStyle(color: _subTextColor),
                              border: InputBorder.none,
                            ),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('My Tasks',
                                  style: TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.bold,
                                      color: _textColor)),
                              const SizedBox(height: 4),
                              AnimatedBuilder(
                                animation: _counterAnim,
                                builder: (_, __) {
                                  final scale = 1.0 +
                                      (1.0 - _counterAnim.value) *
                                          0.3 *
                                          (_counterAnim.value < 0.5 ? 1 : 0);
                                  return Transform.scale(
                                    alignment: Alignment.centerLeft,
                                    scale: scale,
                                    child: Text(
                                      '$_remainingCount task${_remainingCount == 1 ? '' : 's'} remaining',
                                      style: TextStyle(
                                          fontSize: 14,
                                          color: _subTextColor),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                  ),
                  IconButton(
                    icon: Icon(_searchOpen ? Icons.close : Icons.search,
                        color: const Color(0xFF6366F1)),
                    onPressed: () {
                      setState(() {
                        _searchOpen = !_searchOpen;
                        if (!_searchOpen) {
                          _searchController.clear();
                          _searchQuery = '';
                        }
                      });
                    },
                  ),
                  IconButton(
                    icon: Icon(
                        widget.isDark ? Icons.light_mode : Icons.dark_mode,
                        color: const Color(0xFF6366F1)),
                    onPressed: widget.onToggleTheme,
                  ),
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert, color: _subTextColor),
                    onSelected: (v) {
                      if (v == 'export') _exportTasks();
                      if (v == 'import') _importTasks();
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'export',
                        child: Row(children: [
                          Icon(Icons.upload, size: 18),
                          SizedBox(width: 8),
                          Text('Export backup'),
                        ]),
                      ),
                      PopupMenuItem(
                        value: 'import',
                        child: Row(children: [
                          Icon(Icons.download, size: 18),
                          SizedBox(width: 8),
                          Text('Import backup'),
                        ]),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: _cardColor,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 8,
                              offset: const Offset(0, 2)),
                        ],
                      ),
                      child: TextField(
                        controller: _controller,
                        onSubmitted: (_) => _addTask(),
                        style: TextStyle(color: _textColor),
                        decoration: InputDecoration(
                          hintText: 'Add a new task...',
                          hintStyle: TextStyle(color: _subTextColor),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 16),
                          suffixIcon: IconButton(
                            icon: Icon(Icons.calendar_today,
                                size: 20,
                                color: _pendingDueDate != null
                                    ? const Color(0xFF6366F1)
                                    : _subTextColor),
                            onPressed: () => _pickDueDate(),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: _addTask,
                    child: Container(
                      height: 54,
                      width: 54,
                      decoration: BoxDecoration(
                        color: const Color(0xFF6366F1),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.add,
                          color: Colors.white, size: 28),
                    ),
                  ),
                ],
              ),
            ),

            if (_pendingDueDate != null ||
                _pendingTag != null ||
                _pendingPriority != TaskPriority.medium ||
                _pendingRepeat != RepeatType.none)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                child: Wrap(
                  spacing: 8,
                  children: [
                    if (_pendingDueDate != null)
                      Chip(
                        label: Text(DateFormat.yMMMd()
                            .add_jm()
                            .format(_pendingDueDate!)),
                        onDeleted: () =>
                            setState(() => _pendingDueDate = null),
                      ),
                    if (_pendingTag != null)
                      Chip(
                        avatar: const Icon(Icons.label, size: 16),
                        label: Text(_pendingTag!),
                        onDeleted: () => setState(() => _pendingTag = null),
                      ),
                    if (_pendingRepeat != RepeatType.none)
                      Chip(
                        avatar: const Icon(Icons.repeat, size: 16),
                        label: Text(_pendingRepeat.name
                            .toString()
                            .split('.')
                            .last
                            .toUpperCase()),
                        onDeleted: () =>
                            setState(() => _pendingRepeat = RepeatType.none),
                      ),
                    Chip(
                      avatar: Icon(Icons.flag,
                          size: 16,
                          color: _pendingPriority == TaskPriority.high
                              ? Colors.red
                              : _pendingPriority == TaskPriority.low
                                  ? Colors.green
                                  : Colors.orange),
                      label: Text(_pendingPriority.name.toUpperCase()),
                    ),
                  ],
                ),
              ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ...TaskPriority.values.map((p) => Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: GestureDetector(
                            onTap: () =>
                                setState(() => _pendingPriority = p),
                            child: Chip(
                              backgroundColor: _pendingPriority == p
                                  ? (p == TaskPriority.high
                                      ? Colors.red.withOpacity(0.2)
                                      : p == TaskPriority.low
                                          ? Colors.green.withOpacity(0.2)
                                          : Colors.orange.withOpacity(0.2))
                                  : null,
                              label: Text(p.name,
                                  style: const TextStyle(fontSize: 12)),
                            ),
                          ),
                        )),
                    // Repeat selector
                    ...RepeatType.values
                        .where((r) => r != RepeatType.none)
                        .map((r) => Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: GestureDetector(
                                onTap: () => setState(() =>
                                    _pendingRepeat =
                                        _pendingRepeat == r
                                            ? RepeatType.none
                                            : r),
                                child: Chip(
                                  avatar: Icon(Icons.repeat,
                                      size: 14,
                                      color: _pendingRepeat == r
                                          ? const Color(0xFF6366F1)
                                          : Colors.blueGrey),
                                  backgroundColor: _pendingRepeat == r
                                      ? const Color(0xFF6366F1)
                                          .withOpacity(0.2)
                                      : null,
                                  label: Text(r.name,
                                      style:
                                          const TextStyle(fontSize: 12)),
                                ),
                              ),
                            )),
                    ..._availableTags.map((tag) => Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: GestureDetector(
                            onTap: () => setState(() =>
                                _pendingTag =
                                    _pendingTag == tag ? null : tag),
                            child: Chip(
                              backgroundColor: _pendingTag == tag
                                  ? const Color(0xFF6366F1)
                                      .withOpacity(0.2)
                                  : null,
                              avatar: const Icon(Icons.label,
                                  size: 14, color: Colors.blueGrey),
                              label: Text(tag,
                                  style: const TextStyle(fontSize: 12)),
                            ),
                          ),
                        )),
                    GestureDetector(
                      onTap: () async {
                        final ctrl = TextEditingController();
                        await showDialog(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('New Tag'),
                            content: TextField(
                              controller: ctrl,
                              decoration: const InputDecoration(
                                  hintText: 'Tag name'),
                              autofocus: true,
                            ),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(ctx),
                                  child: const Text('Cancel')),
                              ElevatedButton(
                                onPressed: () {
                                  if (ctrl.text.trim().isNotEmpty) {
                                    setState(() =>
                                        _pendingTag = ctrl.text.trim());
                                  }
                                  Navigator.pop(ctx);
                                },
                                child: const Text('OK'),
                              ),
                            ],
                          ),
                        );
                      },
                      child: const Chip(
                        avatar: Icon(Icons.add, size: 14),
                        label: Text('Tag',
                            style: TextStyle(fontSize: 12)),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Row(
                children: [
                  _buildFilterChip('All', TaskFilter.all),
                  const SizedBox(width: 8),
                  _buildFilterChip('Active', TaskFilter.active),
                  const SizedBox(width: 8),
                  _buildFilterChip('Done', TaskFilter.completed),
                  const Spacer(),
                  if (_filterTag != null)
                    InputChip(
                      label: Text(_filterTag!),
                      onDeleted: () => setState(() => _filterTag = null),
                    ),
                ],
              ),
            ),

            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredTasks.isEmpty
                      ? _buildEmptyState()
                      : AnimatedList(
                          key: _listKey,
                          initialItemCount: _filteredTasks.length,
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                          itemBuilder: (context, index, animation) {
                            if (index >= _filteredTasks.length) {
                              return const SizedBox.shrink();
                            }
                            final task = _filteredTasks[index];
                            return _buildAnimatedCard(task, animation);
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnimatedCard(Task task, Animation<double> animation) {
    final slide =
        Tween<Offset>(begin: const Offset(0.3, 0), end: Offset.zero).animate(
            CurvedAnimation(
                parent: animation, curve: Curves.easeOutCubic));
    final fade = CurvedAnimation(parent: animation, curve: Curves.easeIn);
    return SlideTransition(
      position: slide,
      child: FadeTransition(
        opacity: fade,
        child: Dismissible(
          key: ValueKey('task_${task.id}'),
          direction: DismissDirection.endToStart,
          background: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            alignment: Alignment.centerRight,
            decoration: BoxDecoration(
              color: const Color(0xFFEF4444),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.delete, color: Colors.white, size: 28),
          ),
          onDismissed: (_) => _deleteTask(task.id!),
          child: _buildTaskCard(task),
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, TaskFilter value) {
    final selected = _filter == value;
    return GestureDetector(
      onTap: () => setState(() => _filter = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF6366F1) : _cardColor,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : _subTextColor,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildTaskCard(Task task) {
    final dueText = task.dueDate != null
        ? DateFormat.yMMMd().add_jm().format(task.dueDate!)
        : null;
    final isOverdue = task.dueDate != null &&
        !task.isCompleted &&
        task.dueDate!.isBefore(DateTime.now());

    return GestureDetector(
      onLongPress: () => _editTask(task),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: _cardColor,
          border: Border(
            left: BorderSide(color: task.priorityColor, width: 4),
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 2)),
          ],
        ),
        child: Row(
          children: [
            Checkbox(
              value: task.isCompleted,
              onChanged: (_) => _toggleTask(task),
              activeColor: const Color(0xFF6366F1),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4)),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.title,
                    style: TextStyle(
                      fontSize: 16,
                      color: task.isCompleted ? _subTextColor : _textColor,
                      decoration: task.isCompleted
                          ? TextDecoration.lineThrough
                          : TextDecoration.none,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: task.priorityColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(task.priorityLabel,
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: task.priorityColor)),
                      ),
                      if (task.repeat != RepeatType.none)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color:
                                const Color(0xFF6366F1).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.repeat,
                                  size: 10, color: Color(0xFF6366F1)),
                              const SizedBox(width: 2),
                              Text(task.repeatLabel,
                                  style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF6366F1))),
                            ],
                          ),
                        ),
                      if (task.tag != null)
                        GestureDetector(
                          onTap: () =>
                              setState(() => _filterTag = task.tag),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.blueGrey.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text('#${task.tag}',
                                style: const TextStyle(
                                    fontSize: 10,
                                    color: Colors.blueGrey,
                                    fontWeight: FontWeight.w600)),
                          ),
                        ),
                      if (dueText != null)
                        Text(
                          '${isOverdue ? "⚠ " : ""}$dueText',
                          style: TextStyle(
                              fontSize: 10,
                              color: isOverdue
                                  ? const Color(0xFFEF4444)
                                  : _subTextColor,
                              fontWeight: isOverdue
                                  ? FontWeight.w600
                                  : FontWeight.normal),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined,
                  color: Color(0xFF6366F1), size: 20),
              onPressed: () => _editTask(task),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline,
                  color: Color(0xFFEF4444)),
              onPressed: () => _deleteTask(task.id!),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final msg = _searchQuery.isNotEmpty
        ? 'No matches for "$_searchQuery"'
        : _filter == TaskFilter.completed
            ? 'No completed tasks yet'
            : _filter == TaskFilter.active
                ? 'No active tasks — nice!'
                : 'No tasks yet';
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle_outline, size: 80, color: _subTextColor),
          const SizedBox(height: 16),
          Text(msg,
              style: TextStyle(
                  fontSize: 18,
                  color: _subTextColor,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}