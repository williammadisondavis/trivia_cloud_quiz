import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:html_unescape/html_unescape.dart';
import 'package:http/http.dart' as http;
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const TriviaApp());
}

class TriviaApp extends StatelessWidget {
  const TriviaApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Trivia Showdown',
    theme: ThemeData(colorSchemeSeed: Colors.blue, useMaterial3: true),
    home: StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        return snapshot.data == null ? const SignInPage() : TriviaPage(key: ValueKey(snapshot.data!.uid), uid: snapshot.data!.uid);
      },
    ),
  );
}

class SignInPage extends StatefulWidget {
  const SignInPage({super.key});
  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final email = TextEditingController();
  final password = TextEditingController();
  bool busy = false;
  String? error;
  @override
  void dispose() { email.dispose(); password.dispose(); super.dispose(); }
  Future<void> signIn() async {
    if (busy) return;
    setState(() { busy = true; error = null; });
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(email: email.text.trim(), password: password.text);
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => error = 'Sign-in error: ${e.code}');
    } catch (e) {
      if (mounted) setState(() => error = 'Sign-in unavailable: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Trivia Showdown')),
    body: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.quiz_outlined, size: 65),
        const SizedBox(height: 16),
        const Text('Sign in to play', style: TextStyle(fontSize: 25)),
        const SizedBox(height: 18),
        TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email')),
        TextField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'Password'), onSubmitted: (_) => signIn()),
        if (error != null) Padding(padding: const EdgeInsets.all(12), child: Text(error!, style: const TextStyle(color: Colors.red))),
        const SizedBox(height: 20),
        ElevatedButton(onPressed: busy ? null : signIn, child: Text(busy ? 'Signing in...' : 'Sign In')),
      ]),
    ))),
  );
}

class TriviaQuestion {
  final String question;
  final String correctAnswer;
  final List<String> answers;
  TriviaQuestion(this.question, this.correctAnswer, this.answers);
  factory TriviaQuestion.fromJson(Map<String, dynamic> json) {
    if (json['category'] != 'General Knowledge' || json['difficulty'] != 'easy' || json['type'] != 'multiple') {
      throw const FormatException('Unexpected question category or difficulty.');
    }
    final decode = HtmlUnescape().convert;
    final question = decode(json['question'] as String).trim();
    final correct = decode(json['correct_answer'] as String).trim();
    final wrongRaw = json['incorrect_answers'];
    if (wrongRaw is! List || wrongRaw.length != 3) throw const FormatException('Question must have three wrong answers.');
    final wrong = wrongRaw.map((value) => decode(value as String).trim()).toList();
    final answers = [...wrong, correct];
    if (question.isEmpty || answers.any((a) => a.isEmpty) || answers.toSet().length != 4) {
      throw const FormatException('Empty or duplicate question choices.');
    }
    answers.shuffle();
    return TriviaQuestion(question, correct, answers);
  }
}

class TriviaPage extends StatefulWidget {
  final String uid;
  const TriviaPage({super.key, required this.uid});
  @override
  State<TriviaPage> createState() => _TriviaPageState();
}

class _TriviaPageState extends State<TriviaPage> {
  List<TriviaQuestion> questions = [];
  List<String?> selections = [];
  int currentQuestion = 0;
  int score = 0;
  bool loading = true;
  bool finished = false;
  bool pending = false;
  bool cloudVerified = false;
  bool saveUnknown = false;
  bool injectLostAck = false;
  String? error;
  String? saveMessage;
  String? roundId;
  DateTime? lastRequest;
  Map<String, dynamic>? frozenPayload;
  String? verifiedPath;
  final db = FirebaseFirestore.instance;

  @override
  void initState() { super.initState(); loadQuestions(); }
  DocumentReference<Map<String, dynamic>> get attemptRef => db.collection('users').doc(widget.uid).collection('attempts').doc(roundId!);

  Future<void> loadQuestions() async {
    if (pending || saveUnknown || (finished && !cloudVerified && frozenPayload != null)) return;
    final elapsed = lastRequest == null ? const Duration(days: 1) : DateTime.now().difference(lastRequest!);
    if (elapsed < const Duration(seconds: 5)) {
      setState(() => error = 'Please wait ${5 - elapsed.inSeconds} seconds before trying again.');
      return;
    }
    setState(() { loading = true; finished = false; error = null; saveMessage = null; cloudVerified = false; score = 0; currentQuestion = 0; questions = []; selections = []; roundId = null; frozenPayload = null; verifiedPath = null; });
    lastRequest = DateTime.now();
    try {
      final response = await http.get(Uri.parse('https://opentdb.com/api.php?amount=10&category=9&difficulty=easy&type=multiple')).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) throw Exception('HTTP ${response.statusCode}');
      final data = jsonDecode(response.body);
      if (data is! Map<String, dynamic> || data['response_code'] != 0) throw const FormatException('Trivia service returned an API error.');
      final results = data['results'];
      if (results is! List || results.length != 10) throw const FormatException('Expected exactly 10 questions.');
      final loaded = results.map((item) => TriviaQuestion.fromJson(Map<String, dynamic>.from(item as Map))).toList();
      if (!mounted || FirebaseAuth.instance.currentUser?.uid != widget.uid) return;
      setState(() { questions = loaded; selections = List<String?>.filled(10, null); roundId = db.collection('users').doc(widget.uid).collection('attempts').doc().id; loading = false; });
    } catch (e) {
      if (mounted) setState(() { loading = false; error = 'Could not load questions: $e'; });
    }
  }

  void answer(String choice) {
    if (finished || selections[currentQuestion] != null) return;
    setState(() { selections[currentQuestion] = choice; if (choice == questions[currentQuestion].correctAnswer) score++; });
  }
  void next() {
    if (selections[currentQuestion] == null) return;
    setState(() { if (currentQuestion == 9) { finished = true; } else { currentQuestion++; } });
  }
  bool matches(Map<String, dynamic> data) {
    final expected = frozenPayload!;
    return ['schemaVersion','variant','categoryId','questionCount','correctCount'].every((key) => data[key] == expected[key]);
  }
  Future<bool> verifyServer() async {
    final snapshot = await attemptRef.get(const GetOptions(source: Source.server));
    if (!snapshot.exists || snapshot.metadata.hasPendingWrites || snapshot.data() == null || !matches(snapshot.data()!) || snapshot.data()!['submittedAt'] is! Timestamp) {
      throw StateError('Server record missing or does not match this round.');
    }
    return true;
  }
  Future<void> reconcile() async {
    if (pending || frozenPayload == null) return;
    setState(() { pending = true; saveMessage = 'Checking the server...'; });
    try {
      await verifyServer();
      if (!mounted || FirebaseAuth.instance.currentUser?.uid != widget.uid) return;
      setState(() { cloudVerified = true; saveUnknown = false; verifiedPath = attemptRef.path; saveMessage = 'Cloud verified'; });
    } catch (e) {
      if (mounted) setState(() { saveMessage = 'Verification unavailable: $e. Reconnect and check again, or retry the same round.'; });
    } finally { if (mounted) setState(() => pending = false); }
  }
  Future<void> submit() async {
    if (pending || cloudVerified || !finished || roundId == null) return;
    frozenPayload ??= {
      'schemaVersion': 1, 'variant': 'A', 'categoryId': 9, 'questionCount': 10,
      'correctCount': score, 'submittedAt': FieldValue.serverTimestamp(),
    };
    setState(() { pending = true; saveUnknown = false; saveMessage = 'Submitting...'; });
    try {
      // The transaction reads before creating, so a retry never overwrites an attempt.
      await db.runTransaction((transaction) async {
        final existing = await transaction.get(attemptRef);
        if (existing.exists) {
          if (!matches(existing.data()!)) throw StateError('Round ID collision: different score already stored.');
        } else {
          transaction.set(attemptRef, frozenPayload!);
        }
      }).timeout(const Duration(seconds: 10));
      if (injectLostAck) {
        injectLostAck = false;
        if (mounted) setState(() { saveUnknown = true; saveMessage = 'Injected lost acknowledgement. Check the server to recover.'; });
        return;
      }
      if (mounted) setState(() => saveMessage = 'Checking server...');
      await verifyServer();
      if (!mounted || FirebaseAuth.instance.currentUser?.uid != widget.uid) return;
      setState(() { cloudVerified = true; verifiedPath = attemptRef.path; saveMessage = 'Cloud verified'; });
    } on FirebaseException catch (e) {
      if (mounted) setState(() { saveUnknown = e.code == 'unavailable' || e.code == 'deadline-exceeded'; saveMessage = 'Firestore ${e.code}: ${e.message ?? 'Check connection and rules.'}'; });
    } on TimeoutException {
      if (mounted) setState(() { saveUnknown = true; saveMessage = 'Save status unknown. Check the server before retrying.'; });
    } catch (e) {
      if (mounted) setState(() { saveUnknown = true; saveMessage = 'Verification or submission unavailable: $e. Check the server before retrying.'; });
    } finally { if (mounted) setState(() => pending = false); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Trivia Showdown'), actions: [
      IconButton(tooltip: 'Sign out', onPressed: pending || saveUnknown ? null : () => FirebaseAuth.instance.signOut(), icon: const Icon(Icons.logout)),
    ]),
    body: SafeArea(child: loading ? const Center(child: CircularProgressIndicator()) : error != null ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [Text(error!, textAlign: TextAlign.center), const SizedBox(height: 12), ElevatedButton(onPressed: loadQuestions, child: const Text('Try Again'))]))) : finished ? resultsView() : questionView()),
  );

  Widget questionView() {
    final q = questions[currentQuestion];
    final selected = selections[currentQuestion];
    return ListView(padding: const EdgeInsets.all(20), children: [
      Text('Question ${currentQuestion + 1} of 10', style: const TextStyle(fontSize: 18)),
      const SizedBox(height: 12), LinearProgressIndicator(value: (currentQuestion + 1) / 10),
      const SizedBox(height: 18), Text('Score: $score', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      const SizedBox(height: 28), Text(q.question, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.bold)),
      const SizedBox(height: 28),
      ...q.answers.map((choice) => Padding(padding: const EdgeInsets.only(bottom: 12), child: ElevatedButton(
        onPressed: selected == null ? () => answer(choice) : null,
        style: ElevatedButton.styleFrom(
          disabledBackgroundColor: selected == null ? null : choice == q.correctAnswer ? Colors.green.shade200 : choice == selected ? Colors.red.shade200 : Colors.grey.shade100,
          disabledForegroundColor: Colors.black,
          padding: const EdgeInsets.all(18),
        ),
        child: Text(choice, textAlign: TextAlign.center),
      ))),
      if (selected != null) ...[
        const SizedBox(height: 16),
        Text(selected == q.correctAnswer ? '✓ Correct!' : '✗ Incorrect. Correct answer: ${q.correctAnswer}', textAlign: TextAlign.center),
        const SizedBox(height: 16),
        ElevatedButton(onPressed: next, child: Text(currentQuestion == 9 ? 'See Results' : 'Next Question')),
      ],
    ]);
  }

  Widget resultsView() => ListView(padding: const EdgeInsets.all(24), children: [
    const Icon(Icons.emoji_events, size: 65),
    const Text('Round Complete!', textAlign: TextAlign.center, style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
    const SizedBox(height: 12), Text('Final Score: $score / 10', textAlign: TextAlign.center, style: const TextStyle(fontSize: 24)),
    const SizedBox(height: 12), Text('Round ID: $roundId', textAlign: TextAlign.center),
    const SizedBox(height: 18),
    ElevatedButton(onPressed: pending || cloudVerified || saveUnknown ? null : submit, child: Text(pending ? 'Working...' : cloudVerified ? 'Cloud Verified' : 'Submit Score')),
    if (saveUnknown || (frozenPayload != null && !cloudVerified)) ...[
      OutlinedButton(onPressed: pending ? null : reconcile, child: const Text('Check Server')),
      if (!pending) OutlinedButton(onPressed: submit, child: const Text('Retry Same Round')),
    ],
    if (saveMessage != null) Padding(padding: const EdgeInsets.all(8), child: Text(saveMessage!, textAlign: TextAlign.center)),
    if (verifiedPath != null) SelectableText('Server document: $verifiedPath\nScore: $score / 10', textAlign: TextAlign.center),
    const SizedBox(height: 12),
    OutlinedButton(onPressed: pending || saveUnknown || (frozenPayload != null && !cloudVerified) ? null : loadQuestions, child: const Text('Play Again')),
    const Divider(height: 35),
    const Text('Answer Review', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
    ...List.generate(questions.length, (i) => Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${i + 1}. ${questions[i].question}', style: const TextStyle(fontWeight: FontWeight.bold)),
      const SizedBox(height: 6), Text('Your answer: ${selections[i]}'),
      Text('Correct answer: ${questions[i].correctAnswer}'),
      Text(selections[i] == questions[i].correctAnswer ? 'Correct' : 'Incorrect', style: TextStyle(color: selections[i] == questions[i].correctAnswer ? Colors.green.shade700 : Colors.red.shade700)),
    ])))),
  ]);
}
