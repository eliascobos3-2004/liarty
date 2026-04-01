import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Para sonidos
import 'package:hive_flutter/hive_flutter.dart';

class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key});

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  final Box _notesBox = Hive.box('notes');

  // Algoritmo XOR simple para encriptar el texto con el PIN
  String _xorCipher(String text, String pin) {
    final List<int> textBytes = text.codeUnits;
    final List<int> pinBytes = pin.codeUnits;
    final List<int> result = [];
    for (int i = 0; i < textBytes.length; i++) {
      result.add(textBytes[i] ^ pinBytes[i % pinBytes.length]);
    }
    return String.fromCharCodes(result);
  }

  // Abre la página de creación de nota
  void _addNote() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _NoteEditorPage(
          onSave: (title, content, pin, mood, isVictory) {
            final encrypted = _xorCipher(content, pin);
            final List notes =
                List.from(_notesBox.get('list', defaultValue: []));
            notes.add({
              'title': title,
              'content': encrypted,
              'mood': mood,
              'isVictory': isVictory,
              'date': DateTime.now().toIso8601String(),
            });
            _notesBox.put('list', notes);
            setState(() {});
          },
        ),
      ),
    );
  }

  // Abre la página para ver y desencriptar la nota
  void _viewNote(int index, Map note) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _NoteViewerPage(
          note: note,
          xorCipher: _xorCipher,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List notes = _notesBox.get('list', defaultValue: []);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text("Mi Diario de Progreso",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: notes.length,
              itemBuilder: (context, index) {
                final note = notes[index];
                return Card(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: ListTile(
                    leading: Text(note['mood'] ?? "📝",
                        style: const TextStyle(fontSize: 25)),
                    title: Text(note['title'],
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(note['isVictory'] == true
                        ? "🏆 ¡Logro alcanzado!"
                        : "Entrada de diario"),
                    onTap: () => _viewNote(index, note),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () {
                        SystemSound.play(SystemSoundType.click);
                        notes.removeAt(index);
                        _notesBox.put('list', notes);
                        setState(() {});
                      },
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          SystemSound.play(SystemSoundType.click);
          _addNote();
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _NoteEditorPage extends StatefulWidget {
  final Function(
          String title, String content, String pin, String mood, bool isVictory)
      onSave;
  const _NoteEditorPage({required this.onSave});

  @override
  State<_NoteEditorPage> createState() => _NoteEditorPageState();
}

class _NoteEditorPageState extends State<_NoteEditorPage> {
  final titleController = TextEditingController();
  final contentController = TextEditingController();
  final pinController = TextEditingController();
  String selectedMood = "😊";
  bool isVictory = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Nueva Nota")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: titleController,
              decoration: const InputDecoration(labelText: "Título"),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: TextField(
                controller: contentController,
                decoration: const InputDecoration(
                  labelText: "Contenido",
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
                maxLines: null,
                expands: true,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: ["😊", "😐", "😔", "🔥", "🧠"].map((mood) {
                return GestureDetector(
                  onTap: () => setState(() => selectedMood = mood),
                  child: CircleAvatar(
                    backgroundColor:
                        selectedMood == mood ? Colors.black : Colors.white24,
                    child: Text(mood, style: const TextStyle(fontSize: 20)),
                  ),
                );
              }).toList(),
            ),
            SwitchListTile(
              title: const Text("¿Es un logro o victoria?"),
              value: isVictory,
              secondary: const Icon(Icons.emoji_events, color: Colors.amber),
              onChanged: (val) => setState(() => isVictory = val),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: pinController,
              decoration: const InputDecoration(labelText: "PIN (4 dígitos)"),
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 4,
            ),
            ElevatedButton(
              onPressed: () {
                SystemSound.play(SystemSoundType.click);
                if (pinController.text.length == 4 &&
                    titleController.text.isNotEmpty) {
                  widget.onSave(titleController.text, contentController.text,
                      pinController.text, selectedMood, isVictory);
                  Navigator.pop(context);
                }
              },
              child: const Text("Guardar"),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoteViewerPage extends StatefulWidget {
  final Map note;
  final String Function(String text, String pin) xorCipher;

  const _NoteViewerPage({required this.note, required this.xorCipher});

  @override
  State<_NoteViewerPage> createState() => _NoteViewerPageState();
}

class _NoteViewerPageState extends State<_NoteViewerPage> {
  final pinController = TextEditingController();
  String? decryptedContent;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.note['title'])),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: decryptedContent == null
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("Ingresa el PIN para desencriptar:"),
                  TextField(
                    controller: pinController,
                    decoration: const InputDecoration(hintText: "PIN"),
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    maxLength: 4,
                  ),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        decryptedContent = widget.xorCipher(
                            widget.note['content'], pinController.text);
                      });
                    },
                    child: const Text("Desencriptar"),
                  ),
                ],
              )
            : SingleChildScrollView(
                child: Text(decryptedContent!,
                    style: const TextStyle(fontSize: 18, color: Colors.black)),
              ),
      ),
    );
  }
}
