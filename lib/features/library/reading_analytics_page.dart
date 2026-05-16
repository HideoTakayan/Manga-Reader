import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/database_helper.dart';

class ReadingAnalyticsPage extends StatefulWidget {
  const ReadingAnalyticsPage({super.key});

  @override
  State<ReadingAnalyticsPage> createState() => _ReadingAnalyticsPageState();
}

class _ReadingAnalyticsPageState extends State<ReadingAnalyticsPage> {
  int _totalReadMangas = 0;
  int _activeDays = 0;
  bool _isLoading = true;
  List<int> _weeklyCounts = List.filled(7, 0);
  Map<String, int> _genreCounts = const {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    final history = await DatabaseHelper.instance.getHistory(uid);
    final weeklyCounts = List.filled(7, 0);
    final activeDates = <String>{};
    final genres = <String, int>{};
    final now = DateTime.now();
    final weekStart = _dateOnly(now).subtract(Duration(days: now.weekday - 1));

    for (final item in history) {
      final readDate = _dateOnly(item.updatedAt);
      activeDates.add(readDate.toIso8601String());

      final daysFromWeekStart = readDate.difference(weekStart).inDays;
      if (daysFromWeekStart >= 0 && daysFromWeekStart < 7) {
        weeklyCounts[daysFromWeekStart]++;
      }

      final manga = await DatabaseHelper.instance.getLocalManga(item.mangaId);
      if (manga == null) continue;
      for (final genre in manga.genres) {
        final normalized = genre.trim();
        if (normalized.isEmpty) continue;
        genres[normalized] = (genres[normalized] ?? 0) + 1;
      }
    }

    if (!mounted) return;
    setState(() {
      _totalReadMangas = history.length;
      _activeDays = activeDates.length;
      _weeklyCounts = weeklyCounts;
      _genreCounts = Map.fromEntries(
        genres.entries.toList()..sort((a, b) => b.value.compareTo(a.value)),
      );
      _isLoading = false;
    });
  }

  DateTime _dateOnly(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Thong ke doc'),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _buildStatCard(
                        'Truyen da doc',
                        '$_totalReadMangas',
                        Icons.menu_book,
                        Colors.blue,
                      ),
                      const SizedBox(width: 16),
                      _buildStatCard(
                        'Ngay hoat dong',
                        '$_activeDays',
                        Icons.calendar_month,
                        Colors.orange,
                      ),
                    ],
                  ),
                  const SizedBox(height: 30),
                  const Text(
                    'Hoat dong tuan nay',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  _buildWeeklyChart(context),
                  const SizedBox(height: 30),
                  const Text(
                    'The loai da doc',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  _buildGenreChart(context),
                ],
              ),
            ),
    );
  }

  Widget _buildWeeklyChart(BuildContext context) {
    final maxCount = _weeklyCounts.fold<int>(1, (max, value) {
      return value > max ? value : max;
    });

    return Container(
      height: 250,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxCount.toDouble(),
          barTouchData: BarTouchData(enabled: true),
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  const days = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
                  final index = value.toInt();
                  if (index < 0 || index >= days.length) {
                    return const SizedBox.shrink();
                  }
                  return Text(
                    days[index],
                    style: const TextStyle(fontSize: 12),
                  );
                },
              ),
            ),
            leftTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
          ),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          barGroups: [
            for (var i = 0; i < _weeklyCounts.length; i++)
              _makeBar(i, _weeklyCounts[i].toDouble(), maxCount.toDouble()),
          ],
        ),
      ),
    );
  }

  Widget _buildGenreChart(BuildContext context) {
    final topGenres = _genreCounts.entries.take(5).toList();
    if (topGenres.isEmpty) {
      return Container(
        height: 160,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Text('Chua co du lieu the loai'),
      );
    }

    const colors = [
      Colors.redAccent,
      Colors.blueAccent,
      Colors.greenAccent,
      Colors.orangeAccent,
      Colors.purpleAccent,
    ];

    return Container(
      height: 250,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 56,
              sections: [
                for (var i = 0; i < topGenres.length; i++)
                  PieChartSectionData(
                    color: colors[i % colors.length],
                    value: topGenres[i].value.toDouble(),
                    title: topGenres[i].key,
                    radius: 42,
                    titleStyle: const TextStyle(fontSize: 11),
                  ),
              ],
            ),
          ),
          const Text(
            'Top\nthe loai',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  BarChartGroupData _makeBar(int x, double y, double maxY) {
    return BarChartGroupData(
      x: x,
      barRods: [
        BarChartRodData(
          toY: y,
          color: Colors.redAccent,
          width: 16,
          borderRadius: BorderRadius.circular(4),
          backDrawRodData: BackgroundBarChartRodData(
            show: true,
            toY: maxY,
            color: Colors.white10,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 12),
            Text(
              value,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: const TextStyle(fontSize: 12, color: Colors.white54),
            ),
          ],
        ),
      ),
    );
  }
}
