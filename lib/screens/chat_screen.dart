import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Para sonidos
import '../services/chat_service.dart';

class ChatScreen extends StatefulWidget {
  final VoidCallback? onNavigateToAgenda;
  const ChatScreen({super.key, this.onNavigateToAgenda});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final ChatService _chatService = ChatService();
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<Map<String, String>> _messages = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Mensaje inicial de Liarty al cargar la pantalla
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _addLiartyMessage(_chatService.getInitialMessage());
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // Mueve el scroll hacia abajo automáticamente al recibir mensajes
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // Envía el texto del usuario al servicio de chat
  void _sendMessage([String? customText]) async {
    SystemSound.play(SystemSoundType.click); // Sonido al enviar
    final text = (customText ?? _controller.text).trim();
    if (text.isEmpty) return;

    setState(() {
      // Agregamos mensaje visualmente
      _messages.add({"role": "user", "text": text});
      _isLoading = true;
    });
    _controller.clear();
    _scrollToBottom();

    final response = await _chatService.processInput(text);
    _addLiartyMessage(response);
  }

  // Maneja los clics en los botones de opciones (Chips)
  void _handleOption(String opt) async {
    SystemSound.play(SystemSoundType.click); // Sonido al tocar una opción
    if (opt == "Personalizada") {
      final picked = await showDatePicker(
        context: context,
        initialDate: DateTime.now(),
        firstDate: DateTime.now(),
        lastDate: DateTime(2030),
      );
      if (picked != null) {
        _sendMessage("${picked.day}/${picked.month}/${picked.year}");
      }
      // Lanzar el reloj nativo de Android
    } else if (opt == "Seleccionar Hora") {
      final picked = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.now(),
      );
      if (picked != null) {
        _sendMessage("${picked.hour}:${picked.minute}");
      }
    } else if (opt == "Seleccionar Días") {
      final List<String> dias = [
        "Lunes",
        "Martes",
        "Miércoles",
        "Jueves",
        "Viernes",
        "Sábado",
        "Domingo"
      ];
      List<String> seleccionados = [];

      showDialog(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text("Selecciona los días"),
            content: SingleChildScrollView(
              child: Column(
                children: dias
                    .map((dia) => CheckboxListTile(
                          title: Text(dia),
                          value: seleccionados.contains(dia),
                          onChanged: (bool? value) {
                            setDialogState(() {
                              if (value == true) {
                                seleccionados.add(dia);
                              } else {
                                seleccionados.remove(dia);
                              }
                            });
                          },
                        ))
                    .toList(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Cancelar"),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  if (seleccionados.isNotEmpty) {
                    _sendMessage(seleccionados.join(", "));
                  }
                },
                child: const Text("Aceptar"),
              ),
            ],
          ),
        ),
      );
    } else {
      _sendMessage(opt);
    }
  }

  // Recibe la respuesta de Liarty y la muestra en pantalla
  void _addLiartyMessage(String text) {
    if (mounted) {
      if (text.startsWith("COMANDO_LIMPIAR_PANTALLA|")) {
        final realText = text.split('|')[1];
        setState(() {
          _messages.clear();
          _messages.add({"role": "liarty", "text": realText});
          _isLoading = false;
        });
        return;
      }

      // Comando especial para navegar a la pestaña de agenda
      if (text == "COMANDO_MOSTRAR_AGENDA") {
        setState(() {
          _messages.add({
            "role": "liarty",
            "text": "¡Entendido! Te muestro tu agenda actual..."
          });
          _isLoading = false;
        });
        if (widget.onNavigateToAgenda != null) {
          widget.onNavigateToAgenda!();
        }
        return;
      }

      // Animación de entrada para los mensajes de Liarty
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) {
          setState(() {
            _messages.add({"role": "liarty", "text": text});
            _isLoading = false;
          });
          _scrollToBottom();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = _chatService.currentState;
    final options = _chatService.getOptions();

    return Column(
      children: [
        Expanded(
          // Lista de burbujas de chat
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(8.0),
            itemCount: _messages.length,
            itemBuilder: (context, index) {
              final msg = _messages[index];
              final isUser = msg["role"] == "user";
              return Align(
                alignment:
                    isUser ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    // Aumentamos la opacidad para que el texto sea legible sobre imágenes
                    color: isUser
                        ? Colors.white.withOpacity(0.85)
                        : Colors.blue.shade50.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(color: Colors.black12, blurRadius: 4)
                    ],
                  ),
                  child: Text(msg["text"] ?? "",
                      style: const TextStyle(
                          color: Colors.black, fontWeight: FontWeight.w500)),
                ),
              );
            },
          ),
        ),
        if (_isLoading) const LinearProgressIndicator(),
        Padding(
          padding: const EdgeInsets.all(8.0),
          // Área dinámica: Cambia entre Teclado, Botón de inicio o Chips de opciones
          child: Container(
            constraints: const BoxConstraints(minHeight: 60),
            child: (state == ChatState.enteringTitle ||
                    state == ChatState.askingName)
                ? Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          style: const TextStyle(
                            fontSize: 18, // tamaño texto
                            fontWeight: FontWeight.bold, //texto en negrita
                            color: Colors.black, //color de texto
                          ),
                          decoration: const InputDecoration(
                              hintText: "Título del evento...",
                              border: OutlineInputBorder(),
                              filled: true,
                              fillColor: Colors.white), // color de fondo
                          onSubmitted: (_) => _sendMessage(_controller.text),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.send),
                        onPressed: () => _sendMessage(_controller.text),
                      ),
                    ],
                  )
                : state == ChatState.idle
                    // Botón para reiniciar el chat
                    ? Center(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            SystemSound.play(SystemSoundType.click);
                            setState(() {
                              _messages.clear();
                            });
                            _addLiartyMessage(_chatService.getInitialMessage());
                          },
                          icon: const Icon(Icons.add),
                          label: const Text("Nueva Agenda"),
                        ),
                      )
                    // Fila de botones rápidos (Chips)
                    : SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: options
                              .map((opt) => Padding(
                                    padding: const EdgeInsets.only(right: 8.0),
                                    child: ActionChip(
                                      label: Text(opt),
                                      onPressed: () => _handleOption(opt),
                                    ),
                                  ))
                              .toList(),
                        ),
                      ),
          ),
        ),
      ],
    );
  }
}
