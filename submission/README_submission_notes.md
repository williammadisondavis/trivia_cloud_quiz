# Trivia Cloud Quiz — Class A

Flutter Android trivia quiz using Firebase Authentication, Cloud Firestore, and OpenTDB.

## Run

1. Install Flutter and Android SDK.
2. Run `flutter pub get`.
3. Configure the Firebase project `trivia-cloud-quiz-2026` with `flutterfire configure --platforms=android` if needed.
4. Run `flutter run -d emulator-5554` (or another Android device).

## How it works

Sign in, answer ten easy general knowledge multiple choice questions, review your score, then submit it to Firestore. A saved attempt uses the same round ID when retried. The app checks the server before displaying Cloud verified.

## Firestore rules tests

Start the Firestore emulator with `firebase emulators:start --only firestore`, then run `node tests/firestore_security_test.cjs` after installing `@firebase/rules-unit-testing` and `firebase`. Seven security checks passed during testing.

## Evidence

See `evidence/` and `William_Davis_Trivia_Cloud_Quiz_Report.docx`. T12 documents an API connection failure and successful retry, not malformed response injection.
