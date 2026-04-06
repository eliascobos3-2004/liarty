import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';

class StatusScreen extends StatelessWidget {
  const StatusScreen({super.key});

  Map<String, double> _calculateStats(List allEvents, int days) {
    final now = DateTime.now();
    final threshold = now.subtract(Duration(days: days));

    final periodEvents = allEvents.where((e) {
      final date = DateTime.parse(e['data']);
      return date.isAfter(threshold) || days == 1; // Simplificado para hoy
    }).toList();

    if (periodEvents.isEmpty)
      return {"percent": 0.0, "total": 0, "completed": 0};

    final completed =
        periodEvents.where((e) => e['isCompleted'] == true).length;
    return {
      "percent": completed / periodEvents.length,
      "total": periodEvents.length.toDouble(),
      "completed": completed.toDouble(),
    };
  }

  String _getUserRank(int score) {
    if (score >= 1000) return "🏆 Leyenda de Liarty";
    if (score >= 500) return "💎 Maestro de Metas";
    if (score >= 200) return "🥇 Guerrero de Rutinas";
    if (score >= 50) return "🥈 Aspirante Activo";
    return "🥉 Novato Productivo";
  }

  @override
  Widget build(BuildContext context) {
    final prefsBox = Hive.box('liarty_prefs');
    final int score = prefsBox.get('user_score', defaultValue: 0);

    return ValueListenableBuilder(
      valueListenable: Hive.box('events').listenable(),
      builder: (context, box, _) {
        final allEvents = box.get('list', defaultValue: []) as List;
        final routineCompletions = Hive.box('routine_completions').length;
        final totalDone =
            allEvents.where((e) => e['isCompleted'] == true).length +
                routineCompletions;

        final daily = _calculateStats(
            allEvents
                .where(
                    (e) => DateTime.parse(e['data']).day == DateTime.now().day)
                .toList(),
            1);
        final weekly = _calculateStats(allEvents, 7);
        final monthly = _calculateStats(allEvents, 30);

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              const Text(
                "Estado de Cumplimiento",
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                _getUserRank(score),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).primaryColor,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 20),
              _buildStatCard("Progreso Diario", daily, Colors.blue),
              _buildStatCard("Progreso Semanal", weekly, Colors.green),
              _buildStatCard("Progreso Mensual", monthly, Colors.purple),
              const SizedBox(height: 20),
              _buildAchievementsSection(totalDone),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatCard(String title, Map<String, double> stats, Color color) {
    return Card(
        margin: const EdgeInsets.only(bottom: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 15),
              LinearProgressIndicator(
                value: stats['percent'],
                backgroundColor: color.withOpacity(0.1),
                color: color,
                minHeight: 12,
                borderRadius: BorderRadius.circular(10),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("${(stats['percent']! * 100).round()}% completado"),
                  Text(
                      "${stats['completed']?.toInt()}/${stats['total']?.toInt()} tareas"),
                ],
              ),
            ],
          ),
        ));
  }

  Widget _buildAchievementsSection(int completedTotal) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Logros de Liarty",
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          children: [
            _buildBadge("Primer Paso", completedTotal >= 1),
            _buildBadge("Constante", completedTotal >= 10),
            _buildBadge("Maestro", completedTotal >= 50),
          ],
        ),
      ],
    );
  }

  Widget _buildBadge(String label, bool earned) {
    return Opacity(
      opacity: earned ? 1.0 : 0.3,
      child: Chip(
        avatar: const Icon(Icons.emoji_events, size: 16, color: Colors.amber),
        label: Text(label),
        backgroundColor: Colors.white,
      ),
    );
  }
}
