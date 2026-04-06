import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Para sonidos
import 'dart:io';
import 'dart:convert'; // Para jsonEncode
import 'package:hive_flutter/hive_flutter.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:uuid/uuid.dart'; // For generating unique IDs
import 'package:timezone/timezone.dart' as tz;
import '../main.dart';
import '../services/chat_service.dart'
    hide isSameDay; // Ocultamos isSameDay para evitar conflictos

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen>
    with SingleTickerProviderStateMixin {
  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  late TabController _tabController;
  String _priorityFilter = "Todas";
  String _routineDayFilter = DateFormat('EEEE', 'es_ES').format(DateTime.now());

  @override
  void initState() {
    super.initState();
    _selectedDay = DateTime.now();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      setState(() {}); // Para ocultar/mostrar FAB
    });
  }

  // Ventana emergente para confirmar si se cumplió una tarea
  void _showCompletionTemplate(int index, Map event) {
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (context) => CompletionPage(
                  eventIndex: index,
                  eventData: event,
                ))).then((_) => setState(() {}));
  }

  // Actualiza el estado (Check/No check) en Hive
  void _updateTaskStatus(int index, bool completed) {
    final box = Hive.box('events');
    final List<Map<String, dynamic>> list = List.from(
        box.get('list', defaultValue: []).cast<Map<String, dynamic>>());

    if (index >= 0 && index < list.length) {
      final event = list[index];
      if (event['type'] == 'ADD_TASK') {
        // For tasks, update the event directly
        event['isCompleted'] = completed;
        list[index] = event; // Update the list with the modified event
        box.put('list', list);

        if (completed) {
          final prefs = Hive.box('liarty_prefs');
          int currentScore = prefs.get('user_score', defaultValue: 0);
          prefs.put('user_score', currentScore + 10);
        }
      } else if (event['type'] == 'ADD_ROUTINE') {
        // For routines, record completion for the specific day
        final routineCompletionsBox = Hive.box('routine_completions');
        final String routineId = event['id'];
        final String completionDate = isSameDay(_selectedDay, DateTime.now())
            ? DateTime.now().toIso8601String().substring(0, 10)
            : _selectedDay!.toIso8601String().substring(0, 10);

        final String completionKey = '$routineId-$completionDate';

        if (completed) {
          routineCompletionsBox.put(completionKey, true);
          final prefs = Hive.box('liarty_prefs');
          int currentScore = prefs.get('user_score', defaultValue: 0);
          prefs.put('user_score', currentScore + 10);
        } else {
          routineCompletionsBox.delete(completionKey);
        }
      }
      Navigator.pop(context);
      setState(() {});
    }
  }

  // Borra un registro de la base de datos
  void _deleteEvent(int index) {
    final box = Hive.box('events');
    final List<Map<String, dynamic>> list = List.from(
        box.get('list', defaultValue: []).cast<Map<String, dynamic>>());

    if (index >= 0 && index < list.length) {
      final eventToDelete = list[index];
      if (eventToDelete['type'] == 'ADD_ROUTINE') {
        // Delete all completion records for this routine
        final routineCompletionsBox = Hive.box('routine_completions');
        routineCompletionsBox.keys
            .where((key) => key.startsWith(eventToDelete['id']))
            .forEach(routineCompletionsBox.delete);
      }
      list.removeAt(index);
      box.put('list', list);
    }
    setState(() {});
  }

  void _editEvent(int index, Map event) {
    _showAddEventDialog(editIndex: index, existingEvent: event);
  }

  // Diálogo para crear o editar Tareas/Actividades/Rutinas
  void _showAddEventDialog(
      {int? editIndex, Map? existingEvent, String? initialType}) {
    String title = existingEvent?['title'] ?? "";
    String id =
        existingEvent?['id'] ?? Uuid().v4(); // Use existing ID or generate new
    String type = existingEvent?['type'] ?? initialType ?? "ADD_TASK";
    String priority = existingEvent?['priority'] ?? "Casual";
    List<String> routineDays =
        (existingEvent?['routine_days'] ?? "Todos").toString().split(', ');

    DateTime selectedDate = existingEvent != null
        ? DateTime.parse(existingEvent['data'])
        : DateTime.now();
    TimeOfDay selectedTime = existingEvent != null
        ? TimeOfDay.fromDateTime(DateTime.parse(existingEvent['data']))
        : TimeOfDay.now();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(editIndex == null ? "Nuevo Registro" : "Editar Registro"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: TextEditingController(text: title),
                  decoration: const InputDecoration(labelText: "Título"),
                  onChanged: (val) => title = val,
                ),
                DropdownButton<String>(
                  value: type,
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(
                        value: "ADD_TASK", child: Text("Tarea (Alarma)")),
                    DropdownMenuItem(
                        value: "ADD_ROUTINE", child: Text("Rutina")),
                  ],
                  onChanged: (val) => setDialogState(() => type = val!),
                ),
                if (type == "ADD_TASK")
                  DropdownButton<String>(
                    value: priority,
                    isExpanded: true,
                    hint: const Text("Prioridad"),
                    items: ["Urgente", "Importante", "Casual"].map((String p) {
                      return DropdownMenuItem(
                          value: p, child: Text("Prioridad: $p"));
                    }).toList(),
                    onChanged: (val) => setDialogState(() => priority = val!),
                  ),
                if (type == "ADD_ROUTINE")
                  ListTile(
                    title: Text("Días: ${routineDays.join(', ')}"),
                    trailing: const Icon(Icons.edit_calendar),
                    onTap: () async {
                      final List<String> dias = [
                        "Lunes",
                        "Martes",
                        "Miércoles",
                        "Jueves",
                        "Viernes",
                        "Sábado",
                        "Domingo",
                        "Todos"
                      ];
                      await showDialog(
                        context: context,
                        builder: (context) => StatefulBuilder(
                          builder: (context, setStateInternal) => AlertDialog(
                            title: const Text("Selecciona los días"),
                            content: SingleChildScrollView(
                              child: Column(
                                children: dias
                                    .map((d) => CheckboxListTile(
                                          title: Text(d),
                                          value: routineDays.contains(d),
                                          onChanged: (val) {
                                            setStateInternal(() {
                                              if (val == true) {
                                                if (d == "Todos")
                                                  routineDays = ["Todos"];
                                                else {
                                                  routineDays.remove("Todos");
                                                  routineDays.add(d);
                                                }
                                              } else
                                                routineDays.remove(d);
                                            });
                                            setDialogState(() {});
                                          },
                                        ))
                                    .toList(),
                              ),
                            ),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text("OK"))
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ListTile(
                  title: Text(
                      "Fecha: ${DateFormat('dd/MM/yyyy').format(selectedDate)}"),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: selectedDate,
                      firstDate: DateTime.now(),
                      lastDate: DateTime(2030),
                    );
                    SystemSound.play(SystemSoundType.click);
                    if (picked != null)
                      setDialogState(() => selectedDate = picked);
                  },
                ),
                ListTile(
                  title: Text("Hora: ${selectedTime.format(context)}"),
                  trailing: const Icon(Icons.access_time),
                  onTap: () async {
                    final picked = await showTimePicker(
                        context: context, initialTime: selectedTime);
                    SystemSound.play(SystemSoundType.click);
                    if (picked != null)
                      setDialogState(() => selectedTime = picked);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Cancelar")),
            ElevatedButton(
              onPressed: () async {
                SystemSound.play(SystemSoundType.click);
                if (title.isEmpty) return;
                final finalDate = DateTime(
                  selectedDate.year,
                  selectedDate.month,
                  selectedDate.day,
                  selectedTime.hour,
                  selectedTime.minute,
                );

                final box = Hive.box('events');
                final List<Map<String, dynamic>> list = List.from(box.get(
                    'list',
                    defaultValue: []).cast<Map<String, dynamic>>());

                final newEvent = {
                  'id': id, // Ensure ID is part of the event
                  'type': type,
                  'title': title,
                  'data': finalDate.toIso8601String(),
                  'isCompleted': false,
                  'priority': priority,
                  'routine_days':
                      type == "ADD_ROUTINE" && routineDays.isNotEmpty
                          ? routineDays.join(', ')
                          : null,
                };

                if (editIndex != null) {
                  list[editIndex] = newEvent; // Update existing event
                } else {
                  list.add(newEvent); // Add new event
                }
                await box.put('list', list);

                if (type == "ADD_TASK") {
                  // Reschedule notification for tasks
                  await flutterLocalNotificationsPlugin
                      .cancel(id.hashCode); // Cancel old
                  await flutterLocalNotificationsPlugin.zonedSchedule(
                    id.hashCode,
                    'Recordatorio',
                    title,
                    tz.TZDateTime.from(finalDate, tz.local),
                    const NotificationDetails(
                        android: AndroidNotificationDetails(
                            'liarty_alarms', 'Alarmas')),
                    androidScheduleMode:
                        AndroidScheduleMode.exactAllowWhileIdle,
                    uiLocalNotificationDateInterpretation:
                        UILocalNotificationDateInterpretation.absoluteTime,
                    payload: jsonEncode({'id': id, 'type': 'ADD_TASK'}),
                  );
                }
                Navigator.pop(context);
              },
              child: const Text("Guardar"),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 0, // Ocultamos el toolbar para usar solo los Tabs
        bottom: TabBar(
          controller: _tabController,
          onTap: (_) {
            SystemSound.play(
                SystemSoundType.click); // Sonido al cambiar pestaña
          },
          indicatorColor: Colors.black,
          indicatorWeight: 3,
          labelColor: Colors.black,
          unselectedLabelColor: Colors.black38,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold),
          tabs: const [
            Tab(icon: Icon(Icons.task_alt), text: "Tareas"),
            Tab(icon: Icon(Icons.calendar_month), text: "Actividades"),
            Tab(icon: Icon(Icons.repeat), text: "Rutinas"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildFilteredView('ADD_TASK', "tareas"),
          _buildActivitiesTab(),
          _buildFilteredView('ADD_ROUTINE', "rutinas"),
        ],
      ),
      floatingActionButton: _tabController.index == 1
          ? null
          : FloatingActionButton(
              onPressed: () {
                SystemSound.play(SystemSoundType.click);
                _showAddEventDialog(
                    initialType:
                        _tabController.index == 2 ? "ADD_ROUTINE" : "ADD_TASK");
              },
              child: const Icon(Icons.add),
            ),
    );
  }

  // Función para mostrar el horario de Lunes a Viernes
  void _showWeeklySchedule() {
    final box = Hive.box('events');
    final allEvents = box.get('list', defaultValue: []) as List;
    final weekdays = [
      "Lunes",
      "Martes",
      "Miércoles",
      "Jueves",
      "Viernes",
      "Sábado",
      "Domingo"
    ];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Horario Laboral (Lun - Dom)"),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: weekdays.map((dia) {
              final dayEvents = allEvents
                  .where((e) =>
                      e['type'] == 'ADD_ROUTINE' &&
                      (e['routine_days'] ?? "").toString().contains(dia))
                  .toList();

              return ExpansionTile(
                title: Text(dia,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                children: dayEvents.isEmpty
                    ? [const ListTile(title: Text("Sin actividades"))]
                    : dayEvents
                        .map((e) => ListTile(
                              title: Text(e['title']),
                              subtitle: Text(DateFormat('HH:mm')
                                  .format(DateTime.parse(e['data']))),
                            ))
                        .toList(),
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cerrar")),
        ],
      ),
    );
  }

  // Placeholder para la descarga de horario
  Future<void> _downloadSchedule() async {
    final box = Hive.box('events');
    final allEvents = box.get('list', defaultValue: []) as List;
    final routines =
        allEvents.where((e) => e['type'] == 'ADD_ROUTINE').toList();

    if (routines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("No hay rutinas para exportar")));
      return;
    }

    String report = "📅 MI HORARIO DE RUTINAS - LIARTY\n\n";
    for (var r in routines) {
      final time = DateFormat('HH:mm').format(DateTime.parse(r['data']));
      report += "• ${r['title']} [$time] - Días: ${r['routine_days']}\n";
    }
    report += "\nGenerado por EL-33 🚀";

    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/horario_liarty.txt');
    await file.writeAsString(report);

    await Share.shareXFiles([XFile(file.path)],
        text: 'Aquí tienes mi horario generado en Liarty');
  }

  // Vista para Tareas y Rutinas (Listado simple con checkbox)
  Widget _buildFilteredView(String type, String label) {
    return ValueListenableBuilder(
      valueListenable: Hive.box('events').listenable(),
      builder: (context, Box box, Widget? widget) {
        final List<Map<String, dynamic>> allEvents = List.from(
            box.get('list', defaultValue: []).cast<Map<String, dynamic>>());
        List<Map<String, dynamic>> filteredEvents = [];

        if (type == 'ADD_TASK' && _priorityFilter != "Todas") {
          filteredEvents = allEvents
              .where((e) => e['type'] == type)
              .where((e) => e['priority'] == _priorityFilter)
              .toList();
        } else if (type == 'ADD_TASK') {
          filteredEvents = allEvents.where((e) => e['type'] == type).toList();
        } else if (type == 'ADD_ROUTINE') {
          // For routines, we need to generate occurrences for the selected day
          // or show the routine itself if it's active on the selected day.
          // Here, we'll show the routine if it's active on the _routineDayFilter
          filteredEvents = allEvents.where((e) {
            if (e['type'] != 'ADD_ROUTINE') return false;
            return isRoutineActiveOnDay(
                e, _selectedDay ?? DateTime.now(), _routineDayFilter);
          }).toList();
        }

        // Sort events by date for tasks, or by title for routines
        if (type == 'ADD_TASK') {
          filteredEvents.sort((a, b) =>
              DateTime.parse(a['data']).compareTo(DateTime.parse(b['data'])));
        } else {
          filteredEvents
              .sort((a, b) => (a['title'] ?? '').compareTo(b['title'] ?? ''));
        }

        if (filteredEvents.isEmpty) {
          return Column(
            children: [
              if (type == 'ADD_TASK') _buildPriorityFilter(),
              if (type == 'ADD_ROUTINE') ...[
                _buildRoutineDayFilter(),
                _buildRoutineActions(),
              ],
              Expanded(child: _buildEmptyState("No hay $label registradas.")),
            ],
          );
        }

        return Column(
          children: [
            if (type == 'ADD_TASK') _buildPriorityFilter(),
            if (type == 'ADD_ROUTINE') _buildRoutineDayFilter(),
            if (type == 'ADD_ROUTINE') _buildRoutineActions(),
            Expanded(
              child: ListView.builder(
                itemCount: filteredEvents.length,
                itemBuilder: (context, index) {
                  final event =
                      Map<String, dynamic>.from(filteredEvents[index]);
                  bool isCompleted = false;
                  if (event['type'] == 'ADD_TASK') {
                    isCompleted = event['isCompleted'] ?? false;
                  } else if (event['type'] == 'ADD_ROUTINE') {
                    final routineCompletionsBox =
                        Hive.box('routine_completions');
                    final String completionDate =
                        (_selectedDay ?? DateTime.now())
                            .toIso8601String()
                            .substring(0, 10);
                    final String completionKey =
                        '${event['id']}-$completionDate';
                    isCompleted = routineCompletionsBox.get(completionKey,
                        defaultValue: false);
                  }

                  final String priority = event['priority'] ?? "Casual";
                  final int originalIndex =
                      allEvents.indexOf(filteredEvents[index]);

                  Color pColor = Colors.blue;
                  IconData pIcon = Icons.info_outline;
                  if (priority == "Urgente") {
                    pColor = Colors.red;
                    pIcon = Icons.priority_high;
                  }
                  if (priority == "Importante") {
                    pColor = Colors.orange;
                    pIcon = Icons.warning_amber;
                  }

                  return ListTile(
                    leading: Icon(
                      isCompleted ? Icons.check_circle : pIcon,
                      color: isCompleted ? Colors.grey : pColor,
                    ),
                    title: Text(
                      event['title'] ?? 'Sin título',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        decoration:
                            isCompleted ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    subtitle: Text(DateFormat('dd/MM HH:mm')
                        .format(DateTime.parse(event['data']))),
                    onTap: () => _showCompletionTemplate(originalIndex, event),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () {
                            SystemSound.play(SystemSoundType.click);
                            _editEvent(originalIndex, event);
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline,
                              color: Colors.red),
                          onPressed: () {
                            SystemSound.play(SystemSoundType.click);
                            _deleteEvent(originalIndex);
                          },
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildRoutineActions() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _showWeeklySchedule,
              icon: const Icon(Icons.view_week),
              label: const Text("Ver Lun-Dom"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: _downloadSchedule,
            icon: const Icon(Icons.download),
            tooltip: "Descargar Horario",
            style:
                IconButton.styleFrom(backgroundColor: Colors.blueGrey.shade100),
          ),
        ],
      ),
    );
  }

  Widget _buildRoutineDayFilter() {
    final dias = [
      "Lunes",
      "Martes",
      "Miércoles",
      "Jueves",
      "Viernes",
      "Sábado",
      "Domingo"
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: dias
            .map((d) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4.0),
                  child: ChoiceChip(
                    label: Text(d),
                    selected: _routineDayFilter == d,
                    onSelected: (val) {
                      SystemSound.play(SystemSoundType.click);
                      setState(() => _routineDayFilter = d);
                    },
                  ),
                ))
            .toList(),
      ),
    );
  }

  Widget _buildPriorityFilter() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: ["Todas", "Urgente", "Importante", "Casual"]
            .map((p) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4.0),
                  child: ChoiceChip(
                    label: Text(p),
                    selected: _priorityFilter == p,
                    onSelected: (val) {
                      SystemSound.play(SystemSoundType.click);
                      setState(() => _priorityFilter = p);
                    },
                  ),
                ))
            .toList(),
      ),
    );
  }

  // Vista de Actividades (Incluye Calendario y contadores)
  Widget _buildActivitiesTab() {
    return ValueListenableBuilder(
      valueListenable: Hive.box('events').listenable(),
      builder: (context, Box box, Widget? widget) {
        final List<Map<String, dynamic>> allEvents = List.from(
            box.get('list', defaultValue: []).cast<Map<String, dynamic>>());
        final now = _selectedDay ??
            DateTime.now(); // Use selected day for "today" counts

        // Contadores SOLO para hoy
        final tasksToday = allEvents
            .where((e) =>
                e['type'] == 'ADD_TASK' &&
                isSameDay(DateTime.parse(e['data']), now) &&
                !(e['isCompleted'] ?? false))
            .length;

        final routinesToday = allEvents
            .where((e) =>
                e['type'] == 'ADD_ROUTINE' &&
                isRoutineActiveOnDay(
                    e, now)) // Check if routine is active today
            .length;

        // Eventos futuros
        final futureEvents = allEvents
            .where((e) => DateTime.parse(e['data']).isAfter(now))
            .toList();

        return SingleChildScrollView(
          // Permite que el calendario se mueva
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 16.0),
                child: Text(
                  "Hoy ${DateFormat('EEEE d MMMM', 'es_ES').format(now)}\nListado de actividades:",
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildCounterCard(
                        "Tareas hoy", tasksToday, Colors.blue.shade100),
                    _buildCounterCard(
                        "Rutinas hoy", routinesToday, Colors.orange.shade100),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  SystemSound.play(SystemSoundType.click);
                  _showDayStatus(allEvents);
                },
                icon: const Icon(Icons.remove_red_eye),
                label: const Text("Ver Estado"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                ),
              ),
              TableCalendar(
                firstDay: DateTime.utc(2020, 1, 1),
                lastDay: DateTime.utc(2030, 12, 31),
                focusedDay: _focusedDay,
                calendarFormat: CalendarFormat.month, // Fixed to month view
                selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                calendarBuilders: CalendarBuilders(
                  defaultBuilder: (context, day, focusedDay) {
                    // Pintar de amarillo si hay tareas o rutinas ese día
                    final hasEvents = allEvents.any((e) {
                      if (e['type'] == 'ADD_TASK') {
                        return isSameDay(DateTime.parse(e['data']), day);
                      } else if (e['type'] == 'ADD_ROUTINE') {
                        return isRoutineActiveOnDay(e, day);
                      }
                      return false;
                    });
                    if (hasEvents) {
                      return Container(
                          margin: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                              color: Colors.yellow.withOpacity(0.5),
                              shape: BoxShape.circle),
                          child: Center(child: Text(day.day.toString())));
                    }
                    return null;
                  },
                ),
                onDaySelected: (selectedDay, focusedDay) {
                  SystemSound.play(SystemSoundType.click);
                  setState(() {
                    _selectedDay = selectedDay;
                    _focusedDay = focusedDay;
                  });
                },
                onFormatChanged: (format) =>
                    setState(() => _calendarFormat = format),
              ),
              const Divider(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Text("Próximas tareas y eventos:",
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).primaryColor)),
              ),
              Column(
                children: futureEvents
                    .map((e) {
                      // This part needs to be smarter for routines
                      if (e['type'] == 'ADD_TASK') {
                        final date = DateTime.parse(e['data']);
                        return ListTile(
                          leading: const Icon(Icons.calendar_today, size: 16),
                          title: Text(e['title']),
                          subtitle: Text(DateFormat('dd MMM - HH:mm', 'es_ES')
                              .format(date)),
                          onTap: () {
                            SystemSound.play(SystemSoundType.click);
                            setState(() => _selectedDay = date);
                            _showDayStatus(allEvents);
                          },
                        );
                      } else if (e['type'] == 'ADD_ROUTINE') {
                        return ListTile(
                          leading: const Icon(Icons.repeat, size: 16),
                          title: Text(e['title']),
                          subtitle: Text("Rutina: ${e['routine_days']}"),
                          // Tapping a routine in this list should show its details or take to the routine tab
                        );
                      }
                      return const SizedBox.shrink();
                    })
                    .where((widget) => widget != const SizedBox.shrink())
                    .toList(),
              ),
            ],
          ),
        );
      },
    );
  }

  // Widget para mostrar cuando no hay datos
  Widget _buildEmptyState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.inbox, size: 64, color: Colors.grey),
          const SizedBox(height: 10),
          Text(message),
        ],
      ),
    );
  }

  // Tarjetas de contador para la agenda
  Widget _buildCounterCard(String label, int count, Color color) {
    return Card(
      color: color,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Column(
          children: [
            Text(count.toString(),
                style:
                    const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            Text(label, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }

  // Modal que muestra el resumen cronológico del día seleccionado
  void _showDayStatus(List allEvents) {
    final selectedDate = _selectedDay ?? DateTime.now();

    final List<Map<String, dynamic>> dayEvents = [];

    for (var e in allEvents) {
      if (e['type'] == 'ADD_TASK') {
        if (isSameDay(DateTime.parse(e['data']), selectedDate)) {
          dayEvents.add(Map<String, dynamic>.from(e));
        }
      } else if (e['type'] == 'ADD_ROUTINE') {
        if (isRoutineActiveOnDay(e, selectedDate)) {
          // For routines, we need to create a "virtual" event for the selected day
          final routineEvent = Map<String, dynamic>.from(e);
          routineEvent['data'] = DateTime(
                  selectedDate.year,
                  selectedDate.month,
                  selectedDate.day,
                  DateTime.parse(e['data']).hour,
                  DateTime.parse(e['data']).minute)
              .toIso8601String();
          dayEvents.add(routineEvent);
        }
      }
    }
    dayEvents
        .sort((a, b) => (a['data'] as String).compareTo(b['data'] as String));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollController) => Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor.withOpacity(0.2),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                      DateFormat('EEEE', 'es_ES')
                          .format(selectedDate)
                          .toUpperCase(),
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w300)),
                  Text(DateFormat('dd').format(selectedDate),
                      style: const TextStyle(
                          fontSize: 60, fontWeight: FontWeight.bold)),
                  Text(DateFormat('MMMM yyyy', 'es_ES').format(selectedDate),
                      style: const TextStyle(fontSize: 18)),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: dayEvents.length,
                itemBuilder: (context, index) {
                  final e = dayEvents[index];
                  final time = DateFormat('HH:mm')
                      .format(DateTime.parse(e['data'] as String));

                  bool isCompleted = false;
                  if (e['type'] == 'ADD_TASK') {
                    isCompleted = e['isCompleted'] ?? false;
                  } else if (e['type'] == 'ADD_ROUTINE') {
                    final routineCompletionsBox =
                        Hive.box('routine_completions');
                    final String completionDate =
                        selectedDate.toIso8601String().substring(0, 10);
                    final String completionKey = '${e['id']}-$completionDate';
                    isCompleted = routineCompletionsBox.get(completionKey,
                        defaultValue: false);
                  }

                  return ListTile(
                    leading: Text(time,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    title: Text(
                      e['title'],
                      style: TextStyle(
                        decoration:
                            isCompleted ? TextDecoration.lineThrough : null,
                        color: isCompleted ? Colors.grey : Colors.black,
                      ),
                    ),
                    subtitle: Text(
                      e['type'].toString().split('_').last +
                          (e['type'] == 'ADD_ROUTINE'
                              ? ' (${e['routine_days']})'
                              : ''),
                    ),
                    trailing: Icon(
                      e['type'] == 'ADD_TASK'
                          ? Icons.alarm
                          : e['type'] == 'ADD_ROUTINE'
                              ? Icons.repeat
                              : Icons.event,
                      size: 20,
                      color: isCompleted
                          ? Colors.grey
                          : Theme.of(context).primaryColor,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Helper function to check if a routine is active on a given day
bool isRoutineActiveOnDay(Map<String, dynamic> routine, DateTime date,
    [String? filterDay]) {
  if (routine['type'] != 'ADD_ROUTINE') return false;

  final String routineDays = routine['routine_days'] ?? '';
  if (routineDays.isEmpty) return false;

  if (routineDays.contains("Todos los días")) return true;

  final String dayName = DateFormat('EEEE', 'es_ES').format(date);
  final String capitalizedDayName =
      dayName.substring(0, 1).toUpperCase() + dayName.substring(1);

  return routineDays.contains(filterDay ?? capitalizedDayName);
}

class CompletionPage extends StatelessWidget {
  final int eventIndex;
  final Map eventData;

  const CompletionPage(
      {super.key, required this.eventIndex, required this.eventData});

  @override
  Widget build(BuildContext context) {
    // If eventIndex is -1, it means it's a preview or from a notification.
    // In this case, we need to find the actual event in Hive to update its status.
    // If it's from a notification, eventData will contain the full event.
    // If it's a preview, eventData is a dummy.

    // Helper to update status (used by both buttons)
    void handleStatus(bool completed) {
      // If it's a preview, just close the page without saving
      if (eventIndex == -1 && eventData['id'] == null) {
        Navigator.pop(context);
        return;
      }

      final box = Hive.box('events');
      final List<Map<String, dynamic>> list = List.from(
          box.get('list', defaultValue: []).cast<Map<String, dynamic>>());

      final int actualIndex = eventIndex != -1
          ? eventIndex
          : list.indexWhere((e) => e['id'] == eventData['id']);

      if (actualIndex != -1) {
        final event = list[actualIndex];
        if (event['type'] == 'ADD_TASK') {
          event['isCompleted'] = completed;
          list[actualIndex] = event;
          box.put('list', list);
        } else if (event['type'] == 'ADD_ROUTINE') {
          final routineCompletionsBox = Hive.box('routine_completions');
          final String completionDate =
              DateTime.now().toIso8601String().substring(0, 10);
          final String completionKey = '${event['id']}-$completionDate';
          if (completed)
            routineCompletionsBox.put(completionKey, true);
          else
            routineCompletionsBox.delete(completionKey);
        }
        if (completed)
          box.put('user_score',
              (box.get('user_score', defaultValue: 0) as int) + 10);
      }
      Navigator.pop(context);
    }

    final prefs = Hive.box('liarty_prefs');
    final bgType = prefs.get('bg_type', defaultValue: 'color');
    final colorIndex = prefs.get('theme_color_index', defaultValue: 0);
    final imgIndex = prefs.get('bg_image_index', defaultValue: 0);
    final String? customBgPath = prefs.get('custom_bg_path');
    final images = ['img_1.jpeg', 'img_2.jpeg', 'img_3.jpeg'];
    final colors = [
      const Color.fromARGB(255, 84, 129, 39),
      const Color.fromARGB(255, 248, 237, 84),
      const Color.fromARGB(255, 205, 125, 255),
      const Color.fromARGB(255, 75, 172, 179)
    ];

    DecorationImage? decorationImage;
    if (bgType == 'image') {
      decorationImage = DecorationImage(
        image: AssetImage('assets/images/${images[imgIndex]}'),
        fit: BoxFit.cover,
        colorFilter: ColorFilter.mode(
          Colors.black.withOpacity(0.5),
          BlendMode.darken,
        ),
      );
    } else if (bgType == 'custom_image' && customBgPath != null) {
      decorationImage = DecorationImage(
        image: FileImage(File(customBgPath)),
        fit: BoxFit.cover,
        colorFilter: ColorFilter.mode(
          Colors.black.withOpacity(0.5),
          BlendMode.darken,
        ),
      );
    }

    return Scaffold(
      body: Container(
        width: double.infinity,
        // Combinación de color base e imagen con opacidad para resaltar la información
        decoration: BoxDecoration(
          color: colors[colorIndex],
          image: decorationImage,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.task_alt, size: 80, color: Colors.white),
            const SizedBox(height: 20),
            // Texto resaltado con sombras para asegurar legibilidad sobre cualquier fondo
            Text(eventData['title'],
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    shadows: [Shadow(blurRadius: 10, color: Colors.black)])),
            Text(DateFormat('HH:mm').format(DateTime.parse(eventData['data'])),
                style: const TextStyle(
                    fontSize: 24,
                    color: Colors.white70,
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 40),
            const Text("¿Lograste cumplir esta tarea?",
                style: TextStyle(
                    fontSize: 20,
                    color: Colors.white,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 30),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade800,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 30, vertical: 15)),
                    onPressed: () => handleStatus(false),
                    child: Text("NO", style: TextStyle(color: Colors.white))),
                ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade800,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 30, vertical: 15)),
                    onPressed: () {
                      // Changed to use the local handleStatus
                      SystemSound.play(SystemSoundType.click);
                      handleStatus(true);
                    },
                    child: const Text("SÍ",
                        style: TextStyle(color: Colors.white))),
              ],
            )
          ],
        ),
      ),
    );
  }
}
