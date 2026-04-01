import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Para sonidos
import 'package:lunar/lunar.dart';
import 'package:intl/intl.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart'; // Necesario para enviar correos
import '../services/weather_service.dart';
import 'calendar_screen.dart';
import '../main.dart';

class InfoScreen extends StatefulWidget {
  const InfoScreen({super.key});

  @override
  State<InfoScreen> createState() => _InfoScreenState();
}

class _InfoScreenState extends State<InfoScreen> {
  final WeatherService _weatherService = WeatherService();
  Map<String, dynamic>? _weatherData;
  bool _isLoading = true;
  final TextEditingController _suggestionController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadCachedWeather();
    _fetchWeather();
  }

  // Carga el último clima guardado para mostrar algo mientras descarga el nuevo
  void _loadCachedWeather() {
    final box = Hive.box('liarty_prefs');
    final cached = box.get('last_weather');
    if (cached != null) {
      setState(() {
        _weatherData = Map<String, dynamic>.from(cached);
        _isLoading = false;
      });
    }
  }

  // Obtiene ubicación GPS y llama al servicio de OpenWeather
  Future<void> _fetchWeather() async {
    try {
      setState(() => _isLoading = true);

      // Lógica de permisos simplificada para evitar advertencias de licencia
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Servicios de ubicación desactivados');
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Permiso denegado');
        }
      }

      // Obtener posición actual
      Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.low);

      final data = await _weatherService.getWeather(
          position.latitude, position.longitude);

      // Guardar en caché
      final box = Hive.box('liarty_prefs');
      await box.put('last_weather', data);

      setState(() {
        _weatherData = data;
        _isLoading = false;
      });
    } catch (e) {
      if (_weatherData == null) setState(() => _isLoading = false);
      debugPrint("Error cargando clima: $e");
    }
  }

  // Muestra un aviso si el clima indica lluvia
  Widget _buildWeatherAlert() {
    if (_weatherData == null) return const SizedBox.shrink();

    final condition =
        _weatherData!['weather'][0]['main'].toString().toLowerCase();
    final containsRain = condition.contains('rain') ||
        condition.contains('drizzle') ||
        condition.contains('thunderstorm');

    if (!containsRain) return const SizedBox.shrink();

    return Card(
      color: Colors.amber.shade100,
      child: const ListTile(
        leading: Icon(Icons.warning_amber_rounded, color: Colors.orange),
        title: Text("¡Atención!",
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
        subtitle: Text("Hay probabilidad de lluvia. No olvides tu paraguas ☔",
            style: TextStyle(color: Colors.black87)),
      ),
    );
  }

  // Define colores dinámicos según la temperatura
  Color _getWeatherColor() {
    if (_weatherData == null) return Colors.white;
    final temp = _weatherData!['main']['temp'];
    if (temp > 25) return Colors.orange.shade100;
    if (temp < 15) return Colors.blue.shade50;
    return Colors.green.shade50;
  }

  // Sugerencias inteligentes según el clima
  String _getWeatherSuggestion() {
    if (_weatherData == null) return "Obteniendo sugerencias...";
    final condition =
        _weatherData!['weather'][0]['main'].toString().toLowerCase();
    final temp = _weatherData!['main']['temp'];

    if (condition.contains('rain')) {
      return "☔ Lluvia detectada: Lleva paraguas y ten cuidado al caminar.";
    }
    if (condition.contains('cloud')) {
      return "☁️ Día nublado: Ideal para una caminata tranquila o leer.";
    }
    if (temp > 28)
      return "☀️ Hace calor: No olvides hidratarte y usar protector.";

    return "✨ Clima agradable: ¡Un excelente momento para cumplir tus metas!";
  }

  // Función para enviar sugerencias por correo
  Future<void> _sendSuggestion() async {
    final String body = _suggestionController.text.trim();
    if (body.isEmpty) return;

    final Uri emailLaunchUri = Uri(
      scheme: 'mailto',
      path: 'eliascobos3@gmail.com',
      query: 'subject=Sugerencia Liarty App&body=$body',
    );

    if (await canLaunchUrl(emailLaunchUri)) {
      await launchUrl(emailLaunchUri);
      _suggestionController.clear();
    }
  }

  String _getMoonPhase(DateTime date) {
    // Usamos el paquete 'lunar' para obtener la fase astronómica exacta
    final lunar = Lunar.fromDate(date);
    final int day =
        lunar.getDay(); // El día del mes lunar nos da la fase exacta

    // El calendario lunar tiene 29 o 30 días.
    // El día 1 es siempre Luna Nueva, el 15 es Luna Llena.
    if (day == 1) return "Luna Nueva 🌑";
    if (day > 1 && day < 8) return "Luna Creciente 🌒";
    if (day == 8) return "Cuarto Creciente 🌓";
    if (day > 8 && day < 15) return "Gibosa Creciente 🌔";
    if (day == 15) return "Luna Llena 🌕";
    if (day > 15 && day < 22) return "Gibosa Menguante 🌖";
    if (day == 22) return "Cuarto Menguante 🌗";
    if (day > 22) return "Luna Menguante 🌘";

    return "Luna en transición 🌙";
  }

  @override
  Widget build(BuildContext context) {
    final box = Hive.box('liarty_prefs');
    final String name = box.get('user_name', defaultValue: 'Usuario');
    final String evalTime = box.get('evaluation_time', defaultValue: '21:00');

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetchWeather,
              child: ListView(
                padding: const EdgeInsets.all(16.0),
                children: [
                  // Perfil del Usuario
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          const CircleAvatar(
                            radius: 30,
                            backgroundColor: Colors.black,
                            child: Icon(Icons.person,
                                color: Colors.white, size: 40),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            decoration: const InputDecoration(
                                labelText: "Tu Nombre",
                                labelStyle: TextStyle(color: Colors.black),
                                border: InputBorder.none),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 24, fontWeight: FontWeight.bold),
                            controller: TextEditingController(text: name),
                            onSubmitted: (val) => box.put('user_name', val),
                          ),
                          TextButton.icon(
                            onPressed: () async {
                              // Diálogo para cambiar hora de evaluación
                              final picked = await showTimePicker(
                                context: context,
                                initialTime: TimeOfDay(
                                  hour: int.parse(evalTime.split(':')[0]),
                                  minute: int.parse(evalTime.split(':')[1]),
                                ),
                              );
                              if (picked != null) {
                                final timeStr =
                                    "${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}";
                                box.put('evaluation_time', timeStr);
                              }
                            },
                            style: TextButton.styleFrom(
                                foregroundColor: Colors.black),
                            icon: const Icon(Icons.timer),
                            label: Text("Evaluación diaria: $evalTime",
                                style: const TextStyle(color: Colors.black)),
                          ),
                        ],
                      ),
                    ),
                    color:
                        Colors.white.withOpacity(0.9), // Fondo para legibilidad
                  ),
                  const SizedBox(height: 12),
                  // Botón Vista Previa Plantilla
                  ElevatedButton.icon(
                    onPressed: () => _showPreviewTemplate(context),
                    icon: const Icon(Icons.remove_red_eye),
                    label:
                        const Text("Vista Previa: Plantilla de Cumplimiento"),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: const Color.fromARGB(255, 156, 82, 12),
                        foregroundColor: Colors.white),
                  ),
                  const SizedBox(height: 12),
                  // Botón Vista Previa Notificación
                  ElevatedButton.icon(
                    onPressed: _showNotificationPreview,
                    icon: const Icon(Icons.notifications_active),
                    label: const Text("Vista Previa: Notificación"),
                    style: ElevatedButton.styleFrom(
                        backgroundColor:
                            const Color.fromARGB(255, 57, 139, 177),
                        foregroundColor: Colors.white),
                  ),
                  const SizedBox(height: 10),
                  // Tarjeta de Puntuación (Desempeño)
                  Card(
                    color: Colors.white.withOpacity(0.9),
                    child: ListTile(
                      leading: const Icon(Icons.stars, color: Colors.amber),
                      title: const Text("Tu Desempeño",
                          style: TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.bold)),
                      trailing: Text(
                        "${box.get('user_score', defaultValue: 0)} pts",
                        style: const TextStyle(
                            color: Colors.black,
                            fontSize: 20,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _buildWeatherAlert(),
                  const SizedBox(height: 10),
                  // Tarjeta de Clima
                  Card(
                    color: _getWeatherColor(),
                    elevation: 4,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15)),
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.wb_sunny,
                                  size: 48, color: Colors.orange),
                              const SizedBox(width: 15),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _weatherData != null
                                        ? "${_weatherData!['main']['temp'].round()}°C"
                                        : "--°C",
                                    style: const TextStyle(
                                        color: Colors.black,
                                        fontSize: 40,
                                        fontWeight: FontWeight.bold),
                                  ),
                                  Text(
                                    _weatherData != null
                                        ? "${_weatherData!['name']}"
                                        : "Buscando...",
                                    style: const TextStyle(
                                        color: Colors.black, fontSize: 16),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(_getWeatherSuggestion(),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: Colors.black,
                                  fontSize: 15,
                                  fontStyle: FontStyle.italic)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Tarjeta de Fase Lunar
                  Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15)),
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        children: [
                          const Text("Fase Lunar Hoy",
                              style:
                                  TextStyle(color: Colors.black, fontSize: 18)),
                          const SizedBox(height: 10),
                          Text(
                            _getMoonPhase(DateTime.now()),
                            style: const TextStyle(
                                color: Colors.black,
                                fontSize: 24,
                                fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 10),
                          ElevatedButton.icon(
                            onPressed: () async {
                              final picked = await showDatePicker(
                                  context: context,
                                  initialDate: DateTime.now(),
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime(2030));
                              if (picked != null) {
                                final phase = _getMoonPhase(picked);
                                _showMoonDialog(context, picked, phase);
                              }
                            },
                            icon: const Icon(Icons.search),
                            label: const Text("Consultar otra fecha"),
                            style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.black,
                                foregroundColor: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Sección de Ajustes de Apariencia
                  const Text("Personalización",
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Card(
                    child: Column(
                      children: [
                        const ListTile(title: Text("Fondo: Colores Sólidos")),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: List.generate(4, (index) {
                            final colors = [
                              const Color.fromARGB(255, 84, 129, 39),
                              const Color.fromARGB(255, 201, 131, 27),
                              const Color.fromARGB(255, 150, 79, 194),
                              const Color.fromARGB(255, 66, 214, 224)
                            ];
                            return GestureDetector(
                              onTap: () {
                                SystemSound.play(SystemSoundType.click);
                                box.put('bg_type', 'color');
                                box.put('theme_color_index', index);
                              },
                              child: CircleAvatar(
                                backgroundColor: colors[index],
                                radius: 18,
                                child: box.get('theme_color_index',
                                                defaultValue: 0) ==
                                            index &&
                                        box.get('bg_type',
                                                defaultValue: 'color') ==
                                            'color'
                                    ? const Icon(Icons.check,
                                        color: Colors.white)
                                    : null,
                              ),
                            );
                          }),
                        ),
                        const ListTile(title: Text("Fondo: Imágenes")),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: List.generate(3, (index) {
                            return GestureDetector(
                              onTap: () {
                                SystemSound.play(SystemSoundType.click);
                                box.put('bg_type', 'image');
                                box.put('bg_image_index', index);
                              },
                              child: Container(
                                width: 50,
                                height: 50,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  border: box.get('bg_image_index',
                                                  defaultValue: 0) ==
                                              index &&
                                          box.get('bg_type') == 'image'
                                      ? Border.all(
                                          width: 3, color: Colors.black)
                                      : null,
                                  image: DecorationImage(
                                    image: AssetImage(
                                        'assets/images/img_${index + 1}.jpeg'),
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                            );
                          }),
                        ),
                        const SizedBox(height: 15),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Sección de Sugerencias para EL-33
                  const Text("Buzón de Sugerencias",
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        children: [
                          TextField(
                            controller: _suggestionController,
                            maxLines: 3,
                            decoration: const InputDecoration(
                              hintText: "¿Cómo podemos mejorar Liarty?",
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 10),
                          ElevatedButton.icon(
                            onPressed: _sendSuggestion,
                            icon: const Icon(Icons.send),
                            label: const Text("Enviar a soporte"),
                            style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blueGrey,
                                foregroundColor: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),
                  // Marca de empresa EL-33
                  const Center(
                    child: Text(
                      "Desarrollado con dedicación por EL-33 🚀",
                      style: TextStyle(
                          fontWeight: FontWeight.w300,
                          fontStyle: FontStyle.italic),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
    );
  }

  void _showMoonDialog(BuildContext context, DateTime date, String phase) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Fase: ${DateFormat('dd/MM/yyyy').format(date)}"),
        content: Text(phase,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text("Cerrar"))
        ],
      ),
    );
  }

  void _showPreviewTemplate(BuildContext context) {
    // Navegación a pantalla completa con datos de prueba
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CompletionPage(
          eventIndex: -1, // Marcamos como -1 para que no guarde en Hive
          eventData: {
            'title': 'Tarea de Prueba',
            'data': DateTime.now().toIso8601String(),
            'type': 'ADD_TASK'
          },
        ),
      ),
    );
  }

  Future<void> _showNotificationPreview() async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails('liarty_preview', 'Previsualización',
            channelDescription: 'Canal para probar notificaciones',
            importance: Importance.max,
            priority: Priority.high);
    const NotificationDetails details =
        NotificationDetails(android: androidDetails);
    await flutterLocalNotificationsPlugin.show(888, 'Liarty: Vista Previa 🔔',
        '¡Excelente! Así es como recibirás tus avisos.', details);
  }
}
