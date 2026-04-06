import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:uuid/uuid.dart'; // For generating unique IDs
import 'package:timezone/timezone.dart' as tz;
import 'dart:convert'; // For JSON encoding/decoding
import '../main.dart';

enum ChatState {
  idle,
  askingName,
  showingInitialActivities,
  selectingType,
  enteringTitle,
  selectingPriority,
  selectingDay,
  selectingRoutineDays,
  selectingTime, // This state will now directly lead to saving the event
  selectingListadoDay,
  viewingSummary
}

// Función auxiliar para comparar solo fechas (sin hora)
bool isSameDay(DateTime? a, DateTime? b) {
  if (a == null || b == null) return false;
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

class ChatService {
  // Estado actual del flujo del chat
  ChatState _currentState = ChatState.idle;
  // Almacenamiento temporal del evento que se está creando
  Map<String, dynamic> _tempEvent = {};

  ChatState get currentState => _currentState;

  // Mensaje de bienvenida
  String getInitialMessage() {
    final box = Hive.box('events');
    final prefs = Hive.box('liarty_prefs');
    final String userName = prefs.get('user_name', defaultValue: 'amigo');

    final now = DateTime.now();
    final todayTasks = (box.get('list', defaultValue: []) as List)
        .where((e) => isSameDay(DateTime.parse(e['data']), now))
        .toList();

    String summary = "¡Hola de nuevo, $userName! 👋\n\n";
    if (todayTasks.isEmpty) {
      summary += "No tienes tareas pendientes para hoy.";
    } else {
      summary += "Esto tienes para hoy:\n";
      for (var a in todayTasks) {
        summary += "- ${a['title']} (${a['isCompleted'] ? '✅' : '⭕'})\n";
      }
    }

    _currentState = ChatState.showingInitialActivities;
    return "$summary\n\n¿Deseas agendar algo nuevo?";
  }

  // Lógica principal de procesamiento de mensajes
  Future<String> processInput(String input) async {
    String lowInput = input.toLowerCase().trim();

    if (_currentState == ChatState.showingInitialActivities &&
        lowInput == "continuar") {
      _currentState = ChatState.selectingType;
      return "COMANDO_LIMPIAR_PANTALLA|¡Excelente! ¿Qué quieres hacer ahora?";
    }

    switch (_currentState) {
      // Paso 1: Selección de categoría
      case ChatState.selectingType:
        if (lowInput == "listado") {
          _currentState = ChatState.selectingListadoDay;
          return "¿De qué día te gustaría ver el listado de tareas?";
        } else if (lowInput == "tarea") {
          _tempEvent['type'] = "ADD_TASK";
        } else if (lowInput == "rutina") {
          _tempEvent['type'] = "ADD_ROUTINE";
        } else {
          return "Opción no válida. Por favor elige Tarea, Listado o Rutina.";
        }
        _currentState = ChatState.enteringTitle;
        return "Perfecto. ¿Qué título le ponemos?";

      case ChatState.selectingListadoDay:
        DateTime targetDate;
        if (lowInput == "mañana") {
          targetDate = DateTime.now().add(const Duration(days: 1));
        } else {
          try {
            final parts = input.split('/');
            targetDate = DateTime(
                int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
          } catch (e) {
            return "Formato de fecha inválido (DD/MM/AAAA).";
          }
        }

        final box = Hive.box('events');
        final dayTasks = (box.get('list', defaultValue: []) as List)
            .where((e) => isSameDay(DateTime.parse(e['data']), targetDate))
            .toList();

        if (dayTasks.isEmpty) {
          _currentState = ChatState.idle;
          return "No hay tareas registradas para ese día.";
        } else {
          final box = Hive.box('events');
          final tasks = (box.get('list', defaultValue: []) as List)
              .where((e) => isSameDay(DateTime.parse(e['data']), targetDate))
              .toList();

          String summary = "Tareas para ese día:\n";
          for (var t in tasks) {
            summary += "- ${t['title']} (${t['isCompleted'] ? '✅' : '⭕'})\n";
          }
          _currentState = ChatState.viewingSummary;
          return "$summary\n¿Quieres ver el estado en la agenda?";
        }

      // Paso especial: Redirección a Agenda
      case ChatState.viewingSummary:
        _currentState = ChatState.idle;
        if (lowInput == "sí" || lowInput == "si") {
          return "COMANDO_MOSTRAR_AGENDA";
        }
        return "Entendido. ¿Hay algo más en lo que pueda ayudarte?";

      // Paso 2: Nombre del evento
      case ChatState.enteringTitle:
        _tempEvent['title'] = input;
        if (_tempEvent['type'] == "ADD_TASK") {
          _currentState = ChatState.selectingPriority;
          return "¿Qué prioridad tiene esta tarea?";
        }
        if (_tempEvent['type'] == "ADD_ROUTINE") {
          _currentState = ChatState.selectingRoutineDays;
          return "¿Qué días cumplirás esta rutina? Elige uno o 'Todos los días':";
        }
        _currentState = ChatState.selectingDay;
        return "¿Para qué día la programamos?";

      case ChatState.selectingPriority:
        _tempEvent['priority'] = input;
        _currentState = ChatState.selectingDay;
        return "Entendido. ¿Para qué día?";

      case ChatState.selectingRoutineDays:
        _tempEvent['routine_days'] = input;
        // Asignamos el día de hoy como base para que el selector de hora no falle
        _tempEvent['date'] = DateTime.now();
        _currentState = ChatState.selectingTime;
        return "Perfecto. ¿A qué hora la realizarás?";

      // Paso 3: Fecha (Hoy, Mañana o manual)
      case ChatState.selectingDay:
        if (lowInput == "hoy") {
          _tempEvent['date'] = DateTime.now();
        } else if (lowInput == "mañana") {
          _tempEvent['date'] = DateTime.now().add(const Duration(days: 1));
        } else {
          try {
            final parts = input.split('/');
            _tempEvent['date'] = DateTime(
                int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
          } catch (e) {
            return "Error al procesar la fecha. Selecciona una opción.";
          }
        }
        _currentState = ChatState.selectingTime;
        return "Ahora, selecciona la hora en la que quieres programarlo:";

      // Paso 4: Hora (Viene del TimePicker nativo)
      case ChatState.selectingTime:
        try {
          // Parseamos el string "HH:mm" que envía el chat
          final timeParts = input.split(':');
          int h = int.parse(timeParts[0]);
          int m = int.parse(timeParts[1]);

          final String title = _tempEvent['title'] ?? "Sin título";
          final String type = _tempEvent['type'] ?? "ADD_TASK";
          final DateTime baseDate = _tempEvent['date'];

          String ampm = h >= 12 ? "PM" : "AM";
          int displayHour = h > 12 ? h - 12 : (h == 0 ? 12 : h);

          final finalDate =
              DateTime(baseDate.year, baseDate.month, baseDate.day, h, m);
          _tempEvent['finalDate'] = finalDate;

          // Capturamos los datos ANTES de guardar, porque _saveEvent limpia _tempEvent
          final String confirmedTitle = title;
          final String confirmedType = type;
          final String confirmedRoutineDays =
              _tempEvent['routine_days']?.toString() ?? "Hoy";

          await _saveEvent();
          _currentState = ChatState.idle;
          String typeLabel = confirmedType == "ADD_TASK"
              ? "la Tarea"
              : confirmedType == "ADD_ACTIVITY"
                  ? "la Actividad"
                  : "la Rutina";

          String routineInfo =
              confirmedType == "ADD_ROUTINE" ? " ($confirmedRoutineDays)" : "";

          return "¡Perfecto! He agendado $typeLabel: '$confirmedTitle'$routineInfo para las $displayHour:${m.toString().padLeft(2, '0')} $ampm. ¿Quieres agendar algo más?";
        } catch (e) {
          _currentState = ChatState.idle;
          return "Hubo un error al calcular el horario. Reintentemos.";
        }
      default:
        _currentState = ChatState.selectingType;
        return "Dime, ¿qué quieres agendar ahora? (Tarea, Actividad o Rutina)";
    }
  }

  // Devuelve las opciones de botones (chips) según el estado actual
  List<String> getOptions() {
    switch (_currentState) {
      case ChatState.showingInitialActivities:
        return ["Continuar"];
      case ChatState.selectingType:
        return ["Tarea", "Listado", "Rutina"];
      case ChatState.selectingListadoDay:
        return ["Mañana", "Personalizada"];
      case ChatState.selectingPriority:
        return ["Urgente", "Importante", "Casual"];
      case ChatState.selectingDay:
        return ["Hoy", "Mañana", "Personalizada"];
      case ChatState.selectingRoutineDays:
        return ["Seleccionar Días", "Todos los días"];
      case ChatState.selectingTime:
        return ["Seleccionar Hora"];
      case ChatState.viewingSummary:
        return ["Sí", "No"];
      default:
        return [];
    }
  }

  // Guarda el evento en Hive y programa la notificación si es Tarea
  Future<void> _saveEvent() async {
    final box = Hive.box('events');
    final List<Map<String, dynamic>> list = List.from(
        box.get('list', defaultValue: []).cast<Map<String, dynamic>>());
    final String id = Uuid().v4(); // Generate unique ID

    // Creamos el objeto del evento
    list.add({
      'id': id, // Add unique ID
      'type': _tempEvent['type'],
      'title': _tempEvent['title'],
      'data': (_tempEvent['finalDate'] as DateTime).toIso8601String(),
      'isCompleted': false,
      'priority': _tempEvent['priority'] ?? 'Normal',
      'routine_days': _tempEvent['routine_days'] ?? 'Hoy',
    });
    await box.put('list', list);

    // Schedule physical alarm only for tasks
    if (_tempEvent['type'] == "ADD_TASK") {
      // Cancel any existing notification for this ID before scheduling a new one
      await flutterLocalNotificationsPlugin.cancel(id.hashCode);

      await flutterLocalNotificationsPlugin.zonedSchedule(
          id.hashCode, // Use hash of UUID as notification ID
          'Recordatorio',
          _tempEvent['title'],
          tz.TZDateTime.from(_tempEvent['finalDate'], tz.local),
          const NotificationDetails(
              android: AndroidNotificationDetails('liarty_alarms', 'Alarmas')),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          payload: jsonEncode({'id': id, 'type': 'ADD_TASK'})); // Add payload
    }
    _tempEvent = {};
  }
}
