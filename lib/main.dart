import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

const apiKey = String.fromEnvironment('ANTHROPIC_KEY');
const model = 'claude-sonnet-5-5';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Smart Quiz',
        theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
        home: const HomeScreen(),
      );
}

class Question {
  final String question;
  final List<String> options;
  final int answer;
  final String explanation;
  Question(this.question, this.options, this.answer, this.explanation);
  factory Question.fromJson(Map<String, dynamic> j) => Question(
        j['question'],
        List<String>.from(j['options']),
        j['answer'],
        j['explanation'] ?? '',
      );
}

Future<List<Question>> generateQuestions({
  String? prompt,
  File? image,
  int count = 10,
}) async {
  final content = <Map<String, dynamic>>[];
  if (image != null) {
    final isPng = image.path.toLowerCase().endsWith('.png');
    content.add({
      'type': 'image',
      'source': {
        'type': 'base64',
        'media_type': isPng ? 'image/png' : 'image/jpeg',
        'data': base64Encode(await image.readAsBytes()),
      },
    });
  }
  final task = image != null
      ? 'Create $count multiple-choice questions from the content of this image.'
      : 'Create $count multiple-choice questions for: $prompt';
  content.add({'type': 'text', 'text': task});

  final res = await http.post(
    Uri.parse('https://api.anthropic.com/v1/messages'),
    headers: {
      'content-type': 'application/json',
      'x-api-key': apiKey,
      'anthropic-version': '2023-06-01',
    },
    body: jsonEncode({
      'model': model,
      'max_tokens': 4000,
      'system': 'You are a quiz writer. Reply with ONLY a JSON array, no '
          'markdown. Each item: {"question": str, "options": [4 strings], '
          '"answer": index 0-3, "explanation": short str}.',
      'messages': [
        {'role': 'user', 'content': content}
      ],
    }),
  );
  if (res.statusCode != 200) {
    throw Exception('API error ${res.statusCode}: ${res.body}');
  }
  final text = jsonDecode(res.body)['content'][0]['text'] as String;
  final json = text.substring(text.indexOf('['), text.lastIndexOf(']') + 1);
  return (jsonDecode(json) as List).map((e) => Question.fromJson(e)).toList();
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _prompt = TextEditingController();
  double _count = 10;
  bool _loading = false;

  Future<void> _run({File? image}) async {
    if (image == null && _prompt.text.trim().isEmpty) return;
    setState(() => _loading = true);
    try {
      final qs = await generateQuestions(
        prompt: _prompt.text.trim(),
        image: image,
        count: _count.round(),
      );
      if (!mounted) return;
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => QuizScreen(questions: qs)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pick(ImageSource src) async {
    final x = await ImagePicker().pickImage(source: src, imageQuality: 85);
    if (x != null) _run(image: File(x.path));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Smart Quiz')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(padding: const EdgeInsets.all(16), children: [
                TextField(
                  controller: _prompt,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Topic or prompt',
                    hintText: 'Class 10 physics: light, refraction',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Text('Questions: ${_count.round()}'),
                Slider(
                  value: _count,
                  min: 5,
                  max: 30,
                  divisions: 25,
                  onChanged: (v) => setState(() => _count = v),
                ),
                FilledButton.icon(
                  onPressed: () => _run(),
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('Generate from prompt'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => _pick(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Photo to questions (camera)'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => _pick(ImageSource.gallery),
                  icon: const Icon(Icons.photo),
                  label: const Text('Photo to questions (gallery)'),
                ),
              ]),
      );
}

class QuizScreen extends StatefulWidget {
  final List<Question> questions;
  const QuizScreen({super.key, required this.questions});
  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  int _i = 0, _score = 0;
  int? _picked;

  @override
  Widget build(BuildContext context) {
    final qs = widget.questions;
    if (_i >= qs.length) {
      return Scaffold(
        appBar: AppBar(title: const Text('Result')),
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('$_score / ${qs.length}',
                style: Theme.of(context).textTheme.displayMedium),
            const SizedBox(height: 16),
            FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done')),
          ]),
        ),
      );
    }
    final q = qs[_i];
    return Scaffold(
      appBar: AppBar(title: Text('Question ${_i + 1} / ${qs.length}')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text(q.question, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        for (var k = 0; k < q.options.length; k++)
          Card(
            color: _picked == null
                ? null
                : k == q.answer
                    ? Colors.green.shade100
                    : k == _picked
                        ? Colors.red.shade100
                        : null,
            child: ListTile(
              title: Text(q.options[k]),
              onTap: _picked != null
                  ? null
                  : () => setState(() {
                        _picked = k;
                        if (k == q.answer) _score++;
                      }),
            ),
          ),
        if (_picked != null) ...[
          const SizedBox(height: 8),
          Text(q.explanation),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => setState(() {
              _i++;
              _picked = null;
            }),
            child: Text(_i == qs.length - 1 ? 'Finish' : 'Next'),
          ),
        ],
      ]),
    );
  }
}
