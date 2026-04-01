import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Para sonidos del sistema
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:intl/date_symbol_data_local.dart';
import 'screens/chat_screen.dart';
import 'screens/calendar_screen.dart';
import 'screens/info_screen.dart';
import 'screens/status_screen.dart';

// Instancia global para el manejo de notificaciones locales
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

/// Programa la notificación de evaluación diaria
Future<void> scheduleDailyEvaluation(TimeOfDay time) async {
  final now = DateTime.now();
  var scheduledDate =
      DateTime(now.year, now.month, now.day, time.hour, time.minute);

  if (scheduledDate.isBefore(now)) {
    scheduledDate = scheduledDate.add(const Duration(days: 1));
  }

  await flutterLocalNotificationsPlugin.zonedSchedule(
    999, // ID único para la evaluación
    'Evaluación Diaria Liarty 📊',
    'Es hora de revisar tu progreso de hoy. ¡Ven a ver tus estadísticas!',
    tz.TZDateTime.from(scheduledDate, tz.local),
    const NotificationDetails(
      android: AndroidNotificationDetails(
        'liarty_evaluations',
        'Evaluaciones Diarias',
        importance: Importance.max,
        priority: Priority.high,
      ),
    ),
    androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    uiLocalNotificationDateInterpretation:
        UILocalNotificationDateInterpretation.absoluteTime,
    matchDateTimeComponents:
        DateTimeComponents.time, // Se repite cada día a la misma hora
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Configuración inicial de notificaciones para Android
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initializationSettings =
      InitializationSettings(android: initializationSettingsAndroid);

  await flutterLocalNotificationsPlugin.initialize(
    initializationSettings,
    onDidReceiveNotificationResponse: (NotificationResponse details) {
      // Aquí se podría navegar a una pantalla específica o disparar un evento
      // para mostrar la plantilla de cumplimiento.
      debugPrint("Notificación tocada: ${details.payload}");
    },
  );

  // Inicializar zonas horarias para las alarmas programadas
  tz.initializeTimeZones();
  // Inicializar formato de fechas en español
  await initializeDateFormatting('es_ES', null);

  // Inicializar Hive (Base de datos local) y abrir las "cajas" (tablas)
  await Hive.initFlutter();
  await Hive.openBox('liarty_prefs'); // Preferencias: tema, caché de clima
  await Hive.openBox('events'); // Eventos: Tareas, Actividades y Rutinas
  await Hive.openBox('notes'); // Caja para notas encriptadas
  runApp(const LiartyApp());
}

class LiartyApp extends StatelessWidget {
  const LiartyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: Hive.box('liarty_prefs').listenable(),
      builder: (context, box, widget) {
        final int colorIndex = box.get('theme_color_index', defaultValue: 0);
        final String bgType = box.get('bg_type', defaultValue: 'color');
        final int imgIndex = box.get('bg_image_index', defaultValue: 0);

        final appColors = [
          const Color.fromARGB(255, 84, 129, 39),
          const Color.fromARGB(255, 201, 131, 27),
          const Color.fromARGB(255, 150, 79, 194),
          const Color.fromARGB(255, 66, 214, 224)
        ];

        final images = ['img_1.jpeg', 'img_2.jpeg', 'img_3.jpeg'];

        Color selectedColor = appColors[colorIndex];

        return MaterialApp(
          title: 'Liarty',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: selectedColor,
              brightness: Brightness.light,
              primary: selectedColor,
              onSurface: Colors.black,
              onPrimary: Colors.black,
            ),
            // Establecemos Times New Roman como fuente principal (Serif)
            fontFamily: 'serif',
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.transparent,
              elevation: 0,
              foregroundColor: Colors.black,
              titleTextStyle: TextStyle(
                  color: Colors.black,
                  fontSize: 20,
                  fontWeight: FontWeight.bold),
            ),
            textTheme: const TextTheme(
              bodyLarge: TextStyle(color: Colors.black),
              bodyMedium: TextStyle(color: Colors.black),
            ).apply(
              bodyColor: Colors.black,
              displayColor: Colors.black,
            ),
            useMaterial3: true,
          ),
          // Si el nombre es nulo, mostramos la nueva pantalla de Bienvenida
          home: box.get('user_name') == null
              ? const WelcomePage()
              : Container(
                  decoration: bgType == 'color'
                      ? BoxDecoration(color: selectedColor)
                      : BoxDecoration(
                          image: DecorationImage(
                            image:
                                AssetImage('assets/images/${images[imgIndex]}'),
                            fit: BoxFit.cover,
                          ),
                        ),
                  child: const MainScaffold(),
                ),
        );
      },
    );
  }
}

// Pantalla de inicio estilo "Plantilla de Cumplimiento" para nuevos usuarios
class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key});

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  final TextEditingController _nameController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/bienvenida.jpeg'),
            fit: BoxFit.cover,
            colorFilter: ColorFilter.mode(Colors.black45, BlendMode.darken),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(30.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                "¡Bienvenido a Liarty!",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  shadows: [Shadow(blurRadius: 10, color: Colors.black)],
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                "Organiza tu vida, alcanza tus metas.\n¿Cómo deberíamos llamarte?",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 18),
              ),
              const SizedBox(height: 40),
              TextField(
                controller: _nameController,
                style: const TextStyle(color: Colors.white, fontSize: 18),
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  hintText: "Escribe tu nombre aquí...",
                  hintStyle: const TextStyle(color: Colors.white60),
                  filled: true,
                  fillColor: Colors.black38,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 30),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 50, vertical: 15),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15)),
                ),
                onPressed: () {
                  final name = _nameController.text.trim();
                  if (name.isNotEmpty) {
                    // Guardar nombre y refrescar la app
                    Hive.box('liarty_prefs').put('user_name', name);
                  }
                },
                child: const Text("Comenzar",
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MainScaffold extends StatefulWidget {
  const MainScaffold({super.key});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  int _selectedIndex = 0;
  double _logoScale =
      1.2; // Empezamos en 1.2 para forzar el inicio de la animación

  // Cambia la pestaña actual (usado desde el Chat o el menú inferior)
  void _changeTab(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Hacemos el fondo transparente para que se vea la decoración del Container principal
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        // Eliminamos 'const' de aquí si es que estaba, ya que TweenAnimationBuilder no es constante
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Liarty by "),
            // TweenAnimationBuilder crea una animación simple sin necesidad de controladores complejos
            TweenAnimationBuilder<double>(
              // Corregido: Ahora el destino es diferente al origen para que inicie el movimiento
              tween: Tween<double>(begin: 1.0, end: _logoScale),
              duration: const Duration(seconds: 2),
              curve: Curves.easeInOutSine,
              builder: (context, value, child) {
                return Transform.scale(
                  scale: value,
                  child: Opacity(
                    opacity: (value - 0.5).clamp(0.6, 1.0),
                    child: child,
                  ),
                );
              },
              // Al terminar la animación, cambiamos el objetivo para que se repita infinitamente
              onEnd: () {
                setState(() {
                  _logoScale = _logoScale == 1.0 ? 1.2 : 1.0;
                });
              },
              child: const Text(
                "EL-33",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontFamily: "serif",
                  color: Color.fromARGB(
                      255, 19, 75, 7), // Color distintivo para tu marca
                ),
              ),
            ),
          ],
        ),
        centerTitle: true,
      ),
      // IndexedStack mantiene el estado de las pantallas al cambiar entre ellas
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          ChatScreen(onNavigateToAgenda: () => _changeTab(1)),
          const CalendarScreen(),
          const StatusScreen(),
          const InfoScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (int index) {
          // Ejecuta un sonido de clic al tocar el menú
          SystemSound.play(SystemSoundType.click);
          setState(() {
            _selectedIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.chat), label: 'Chat'),
          NavigationDestination(
              icon: Icon(Icons.calendar_month), label: 'Agenda'),
          NavigationDestination(icon: Icon(Icons.analytics), label: 'Estado'),
          NavigationDestination(icon: Icon(Icons.wb_sunny), label: 'Info'),
        ],
      ),
    );
  }
}
