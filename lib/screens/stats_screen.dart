import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../models/task.dart';
import '../database/database_helper.dart';

class StatsScreen extends StatefulWidget {
  final bool isDark;

  const StatsScreen({super.key, required this.isDark});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  bool _isLoading = true;

  int _total = 0;
  int _completed = 0;
  int _active = 0;
  Map<String, int> _priorityBreakdown = {'low': 0, 'medium': 0, 'high': 0};
  List<int> _perDay = List<int>.filled(7, 0);

  Color get _cardColor =>
      widget.isDark ? const Color(0xFF1F2937) : Colors.white;
  Color get _textColor =>
      widget.isDark ? Colors.white : const Color(0xFF1F2937);
  Color get _subTextColor =>
      widget.isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final tasks = await _dbHelper.getTasks();
    final priority = await _dbHelper.getPriorityBreakdown();
    final perDay = await _dbHelper.getCompletedPerLast7Days();
    if (!mounted) return;
    setState(() {
      _total = tasks.length;
      _completed = tasks.where((t) => t.isCompleted).length;
      _active = _total - _completed;
      _priorityBreakdown = priority;
      _perDay = perDay;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('Statistics',
                style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: _textColor)),
            const SizedBox(height: 20),

            // KPI cards
            Row(
              children: [
                _kpiCard('Total', '$_total', const Color(0xFF6366F1)),
                const SizedBox(width: 12),
                _kpiCard('Done', '$_completed', const Color(0xFF10B981)),
                const SizedBox(width: 12),
                _kpiCard('Active', '$_active', const Color(0xFFF59E0B)),
              ],
            ),
            const SizedBox(height: 24),

            // Completion %
            _sectionCard(
              title: 'Completion Rate',
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(
                      value: _total == 0 ? 0 : _completed / _total,
                      minHeight: 14,
                      backgroundColor:
                          const Color(0xFF6366F1).withOpacity(0.15),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                          Color(0xFF10B981)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _total == 0
                        ? '0%'
                        : '${(_completed / _total * 100).toStringAsFixed(0)}% completed',
                    style: TextStyle(color: _subTextColor, fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Bar chart: tasks completed per last 7 days
            _sectionCard(
              title: 'Completed (last 7 days)',
              child: SizedBox(
                height: 180,
                child: BarChart(
                  BarChartData(
                    alignment: BarChartAlignment.spaceAround,
                    borderData: FlBorderData(show: false),
                    gridData: FlGridData(show: false),
                    titlesData: FlTitlesData(
                      leftTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                      topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (value, meta) {
                            final days = [
                              'M',
                              'T',
                              'W',
                              'T',
                              'F',
                              'S',
                              'S'
                            ];
                            final todayIdx = DateTime.now().weekday - 1;
                            final idx =
                                (todayIdx - 6 + value.toInt()) % 7;
                            return Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                days[idx],
                                style: TextStyle(
                                    fontSize: 11, color: _subTextColor),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    barGroups: List.generate(7, (i) {
                      return BarChartGroupData(x: i, barRods: [
                        BarChartRodData(
                          toY: _perDay[i].toDouble(),
                          color: const Color(0xFF6366F1),
                          width: 16,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ]);
                    }),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Pie chart: priority breakdown
            _sectionCard(
              title: 'Priority Breakdown',
              child: SizedBox(
                height: 200,
                child: Row(
                  children: [
                    Expanded(
                      child: PieChart(
                        PieChartData(
                          sectionsSpace: 2,
                          centerSpaceRadius: 40,
                          sections: [
                            _pieSection('High', _priorityBreakdown['high']!,
                                const Color(0xFFEF4444)),
                            _pieSection('Medium', _priorityBreakdown['medium']!,
                                const Color(0xFFF59E0B)),
                            _pieSection('Low', _priorityBreakdown['low']!,
                                const Color(0xFF10B981)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _legend('High', const Color(0xFFEF4444),
                            _priorityBreakdown['high']!),
                        _legend('Medium', const Color(0xFFF59E0B),
                            _priorityBreakdown['medium']!),
                        _legend('Low', const Color(0xFF10B981),
                            _priorityBreakdown['low']!),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 60),
          ],
        ),
      ),
    );
  }

  PieChartSectionData _pieSection(String name, int value, Color color) {
    return PieChartSectionData(
      value: value.toDouble(),
      color: color,
      radius: 60,
      title: value == 0 ? '' : '$value',
      titleStyle: const TextStyle(
          fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
    );
  }

  Widget _legend(String label, Color color, int count) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 12,
              height: 12,
              decoration:
                  BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text('$label: $count',
              style: TextStyle(fontSize: 13, color: _subTextColor)),
        ],
      ),
    );
  }

  Widget _kpiCard(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: _cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.3), width: 1.5),
        ),
        child: Column(
          children: [
            Text(value,
                style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: color)),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(fontSize: 12, color: _subTextColor)),
          ],
        ),
      ),
    );
  }

  Widget _sectionCard({required String title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: _textColor)),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}