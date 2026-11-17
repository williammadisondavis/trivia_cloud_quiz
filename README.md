# Trivia Cloud Quiz - Class A

Flutter Android quiz with Firebase Authentication, OpenTDB and Cloud Firestore.

GitHub repository: https://github.com/williammadisondavis/trivia_cloud_quiz
Firebase project ID: trivia-cloud-quiz-2026

## Requirements

Flutter SDK, Android SDK/emulator, a Firebase project with Email/Password Authentication enabled and a Firestore database.

## Run on Android

```bash
cd ~/Desktop/trivia_cloud_quiz
flutter pub get
flutterfire configure --platforms=android
flutter run
```

The existing Android Firebase configuration is included with the project. The Firebase project must be accessible to the tester. Do not commit real test passwords.

## App flow

Sign in, load ten easy General Knowledge multiple choice questions, answer each once, review the score, and submit the completed attempt. The app creates the score under:

`users/{authenticatedUid}/attempts/{roundId}`

Each attempt has exactly six fields: `schemaVersion` (1), `variant` (A), `categoryId` (9), `questionCount` (10), `correctCount` (0 through 10), and `submittedAt` (server timestamp). Firestore security rules allow only the owner to create and read valid attempts. Updates and deletes are blocked.

The app uses a transaction to check whether the round ID already exists. A retry uses the same round ID; a different score under that ID is treated as a collision. `Cloud verified` appears only after a server-only read matches the expected score and timestamp. If the connection fails, Check Server and Retry Same Round are available.

## Validation and evidence

Run:

```bash
flutter analyze
flutter build apk --release
```

The release APK output is `build/app/outputs/flutter-apk/app-release.apk`.

Firestore rules tests (requires Firebase CLI, Node.js, and the Firestore emulator):

```bash
firebase emulators:start --only firestore
# In another terminal:
npm install --no-save @firebase/rules-unit-testing firebase
node tests/firestore_security_test.cjs
```

Seven rules tests passed on the local emulator. Other observed UI checks and their screenshots are in `evidence/`. Full descriptions and the critical thinking answers are in `ICA16_A_William_Davis.docx`.

## Files

- `lib/main.dart`: Flutter quiz, authentication, OpenTDB fetching, scoring, Firestore saving and verification
- `firestore.rules`: owner and schema restrictions
- `firebase.json`: Firebase project and emulator configuration
- `tests/firestore_security_test.cjs`: local rules tests
- `evidence/`: screenshots from testing
- `submission/ICA16_A_William_Davis.docx`: written report
- `submission/ICA16_A_William_Davis.apk`: release APK
