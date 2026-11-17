import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:html_unescape/html_unescape.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const TriviaApp());
}

class TriviaApp extends StatelessWidget {
  const TriviaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Trivia Showdown',
      theme: ThemeData(
        colorSchemeSeed: Colors.blue,
        useMaterial3: true,
      ),
      home: const TriviaPage(),
    );
  }
}

// Stores one trivia question and its answers.
class TriviaQuestion {
  final String question;
  final String correctAnswer;
  final List<String> answers;

  TriviaQuestion({
    required this.question,
    required this.correctAnswer,
    required this.answers,
  });

  factory TriviaQuestion.fromJson(Map<String, dynamic> json) {
    final unescape = HtmlUnescape();

    final correct = unescape.convert(
      json['correct_answer'] as String,
    );

    final wrong = (json['incorrect_answers'] as List)
        .map((answer) => unescape.convert(answer as String))
        .toList();

    final choices = [...wrong, correct];
    choices.shuffle();

    return TriviaQuestion(
      question: unescape.convert(json['question'] as String),
      correctAnswer: correct,
      answers: choices,
    );
  }
}

class TriviaPage extends StatefulWidget {
  const TriviaPage({super.key});

  @override
  State<TriviaPage> createState() => _TriviaPageState();
}

class _TriviaPageState extends State<TriviaPage> {
  List<TriviaQuestion> questions = [];

  bool loading = true;
  bool finished = false;
  bool syncing = false;
  bool synced = false;

  String? error;
  String? selectedAnswer;

  int currentQuestion = 0;
  int score = 0;

  @override
  void initState() {
    super.initState();
    loadQuestions();
  }

  // Gets five live questions from the trivia API.
  Future<void> loadQuestions() async {
    setState(() {
      loading = true;
      finished = false;
      syncing = false;
      synced = false;
      error = null;
      selectedAnswer = null;
      currentQuestion = 0;
      score = 0;
      questions = [];
    });

    try {
      final url = Uri.parse(
        'https://opentdb.com/api.php?amount=5&category=9&difficulty=easy&type=multiple',
      );

      final response = await http.get(url).timeout(
        const Duration(seconds: 10),
      );

      if (response.statusCode != 200) {
        throw Exception('HTTP error: ${response.statusCode}');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (data['response_code'] != 0) {
        throw Exception('Trivia API did not return valid questions.');
      }

      final results = data['results'] as List<dynamic>;

      if (results.length != 5) {
        throw Exception('Expected five trivia questions.');
      }

      final loadedQuestions = results.map((item) {
        return TriviaQuestion.fromJson(
          Map<String, dynamic>.from(item as Map),
        );
      }).toList();

      if (!mounted) return;

      setState(() {
        questions = loadedQuestions;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        error = 'Could not load questions.\n$e';
        loading = false;
      });
    }
  }

  // Only counts the first answer selected.
  void answerQuestion(String answer) {
    if (selectedAnswer != null) return;

    setState(() {
      selectedAnswer = answer;

      if (answer == questions[currentQuestion].correctAnswer) {
        score++;
      }
    });
  }

  void nextQuestion() {
    if (selectedAnswer == null) return;

    setState(() {
      if (currentQuestion < questions.length - 1) {
        currentQuestion++;
        selectedAnswer = null;
      } else {
        finished = true;
      }
    });
  }

  // Classroom simulation. No real cloud write occurs.
  Future<void> syncScore() async {
    if (syncing || synced) return;

    setState(() {
      syncing = true;
    });

    final payload = {
      'score': score,
      'total': questions.length,
    };

    debugPrint('Simulated score payload: ${jsonEncode(payload)}');

    await Future<void>.delayed(const Duration(seconds: 2));

    if (!mounted) return;

    setState(() {
      syncing = false;
      synced = true;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Score sync simulated successfully!'),
      ),
    );
  }

  Color answerColor(String answer, String correct) {
    if (selectedAnswer == null) {
      return Colors.white;
    }

    if (answer == correct) {
      return Colors.green.shade200;
    }

    if (answer == selectedAnswer) {
      return Colors.red.shade200;
    }

    return Colors.white;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trivia Showdown'),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: loading ? null : loadQuestions,
            icon: const Icon(Icons.refresh),
            tooltip: 'Load new questions',
          ),
        ],
      ),
      body: SafeArea(
        child: buildContent(),
      ),
    );
  }

  Widget buildContent() {
    if (loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading trivia questions...'),
          ],
        ),
      );
    }

    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 50),
              const SizedBox(height: 16),
              Text(error!, textAlign: TextAlign.center),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: loadQuestions,
                child: const Text('Try Again'),
              ),
            ],
          ),
        ),
      );
    }

    if (finished) {
      return buildResults();
    }

    return buildQuestion();
  }

  Widget buildQuestion() {
    final question = questions[currentQuestion];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Question ${currentQuestion + 1} of ${questions.length}',
            style: const TextStyle(fontSize: 18),
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: (currentQuestion + 1) / questions.length,
            minHeight: 8,
          ),
          const SizedBox(height: 16),
          Text(
            'Score: $score',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 30),
          Text(
            question.question,
            style: const TextStyle(
              fontSize: 23,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 30),

          // Display all four possible answers.
          ...question.answers.map((answer) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ElevatedButton(
                onPressed: () => answerQuestion(answer),
                style: ElevatedButton.styleFrom(
                  backgroundColor: answerColor(
                    answer,
                    question.correctAnswer,
                  ),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.all(18),
                ),
                child: Text(
                  answer,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 17),
                ),
              ),
            );
          }),

          if (selectedAnswer != null) ...[
            const SizedBox(height: 16),
            Text(
              selectedAnswer == question.correctAnswer
                  ? 'Correct!'
                  : 'Incorrect! Correct answer: ${question.correctAnswer}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: nextQuestion,
              child: Text(
                currentQuestion == questions.length - 1
                    ? 'See Results'
                    : 'Next Question',
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget buildResults() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.emoji_events, size: 75),
            const SizedBox(height: 20),
            const Text(
              'Round Complete!',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Final Score: $score / ${questions.length}',
              style: const TextStyle(fontSize: 24),
            ),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: syncing || synced ? null : syncScore,
              child: Text(
                syncing
                    ? 'Simulating Sync...'
                    : synced
                        ? 'Simulation Complete'
                        : 'Sync Score (Simulation)',
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Classroom simulation only. No score is sent to a server.',
              textAlign: TextAlign.center,
            ),
            if (synced) ...[
              const SizedBox(height: 12),
              Text(
                'Simulated payload: {"score": $score, "total": ${questions.length}}',
                textAlign: TextAlign.center,
              ),
              const Text('Simulated sync successful!'),
            ],
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: loadQuestions,
              child: const Text('Play Again'),
            ),
          ],
        ),
      ),
    );
  }
}
