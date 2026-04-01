import 'dart:convert';
import 'package:http/http.dart' as http;

class WeatherService {
  // Reemplaza con tu API Key de OpenWeatherMap
  final String _apiKey = '1d16b0ceae226e08a29d68828c8ad0f0';
  final String _baseUrl = 'https://api.openweathermap.org/data/2.5/weather';

  Future<Map<String, dynamic>> getWeather(double lat, double lon) async {
    if (_apiKey == 'TU_API_KEY_DE_OPENWEATHER') {
      throw Exception('Por favor, configura tu API Key de OpenWeatherMap');
    }

    final url = Uri.parse(
        '$_baseUrl?lat=$lat&lon=$lon&appid=$_apiKey&units=metric&lang=es');

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Error al obtener clima: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error de conexión: $e');
    }
  }
}
