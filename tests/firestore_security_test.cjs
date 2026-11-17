const fs = require('fs');
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails
} = require('@firebase/rules-unit-testing');
const {
  doc, setDoc, getDoc, updateDoc, deleteDoc, serverTimestamp
} = require('firebase/firestore');

async function main() {
  const env = await initializeTestEnvironment({
    projectId: 'trivia-cloud-quiz-2026',
    firestore: {
      host: '127.0.0.1',
      port: 8080,
      rules: fs.readFileSync('firestore.rules', 'utf8')
    }
  });

  try {
    const userA = env.authenticatedContext('userA').firestore();
    const userB = env.authenticatedContext('userB').firestore();

    const path = 'users/userA/attempts/test-round';
    const record = {
      schemaVersion: 1,
      variant: 'A',
      categoryId: 9,
      questionCount: 10,
      correctCount: 7,
      submittedAt: serverTimestamp()
    };

    await assertSucceeds(setDoc(doc(userA, path), record));
    console.log('PASS: User A creates a valid score');

    await assertSucceeds(getDoc(doc(userA, path)));
    console.log('PASS: User A reads their score');

    await assertFails(getDoc(doc(userB, path)));
    console.log('PASS: User B cannot read User A score');

    await assertFails(setDoc(doc(userB, 'users/userA/attempts/other'), record));
    console.log('PASS: User B cannot write User A score');

    await assertFails(updateDoc(doc(userA, path), { correctCount: 10 }));
    console.log('PASS: Saved score cannot be edited');

    await assertFails(deleteDoc(doc(userA, path)));
    console.log('PASS: Saved score cannot be deleted');

    await assertFails(setDoc(doc(userA, 'users/userA/attempts/invalid'), {
      ...record,
      correctCount: 15
    }));
    console.log('PASS: Invalid score is rejected');

    console.log('ALL 7 SECURITY TESTS PASSED');
  } finally {
    await env.cleanup();
  }
}

main().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
