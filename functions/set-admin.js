/**
 * Grant the admin claim on the Auth emulator.
 * Usage: node set-admin.js worker@worky.test
 */
const admin = require('firebase-admin');

process.env.FIREBASE_AUTH_EMULATOR_HOST =
  process.env.FIREBASE_AUTH_EMULATOR_HOST || '127.0.0.1:9099';

admin.initializeApp({ projectId: 'worky-93fbc' });

const email = process.argv[2];
if (!email) {
  console.error('email required');
  process.exit(1);
}

admin
  .auth()
  .getUserByEmail(email)
  .then((user) => admin.auth().setCustomUserClaims(user.uid, { admin: true }))
  .then(() => {
    console.log(`admin set for ${email}`);
    process.exit(0);
  })
  .catch((err) => {
    console.error(err);
    process.exit(1);
  });
