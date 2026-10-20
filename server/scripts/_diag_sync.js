// Temporary read-only diagnostic: mint an ID token for an EXISTING account
// and replay it against the running API to see what firebase-sync returns.
// No DB writes are expected (that account already has a matching row).
//
// SECURITY: never commit a real API key here. Set FIREBASE_WEB_API_KEY
// in the environment (the value is public-ish but baking it into a
// committed script is still a smell). If this file ever contained a
// real key, rotate it in Firebase Console -> Project settings -> API keys.
import { readFileSync } from 'node:fs';
import { initializeApp, cert } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';

const raw = process.env.FIREBASE_SERVICE_ACCOUNT
  ? JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT)
  : JSON.parse(
      readFileSync(new URL('../firebase-service-account.json', import.meta.url), 'utf8'),
    );
initializeApp({ credential: cert(raw) });

const API_KEY = process.env.FIREBASE_WEB_API_KEY;
if (!API_KEY) {
  console.error('FIREBASE_WEB_API_KEY env var is required (Firebase Console -> Project settings -> API keys).');
  process.exit(1);
}
const uid = process.argv[2] ?? 'dbj9lluHJGPLsq2oG4GkBFU1NWz1';

const custom = await getAuth().createCustomToken(uid, { probe: true });
const r = await fetch(
  `https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=${API_KEY}`,
  {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ token: custom, returnSecureToken: true }),
  },
);
const j = await r.json();
if (!j.idToken) {
  console.log('token exchange FAILED', r.status, JSON.stringify(j));
  process.exit(1);
}
console.log('got ID token for uid', j.localId);

for (const url of ['http://localhost:8080/api/auth/firebase-sync', 'http://localhost:8080/api/auth/me']) {
  const res = await fetch(url, {
    method: url.includes('sync') ? 'POST' : 'GET',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${j.idToken}`,
    },
    body: url.includes('sync')
      ? JSON.stringify({ display_name: '', email: j.email })
      : undefined,
  });
  const body = await res.text();
  console.log(url, '->', res.status, body.slice(0, 300));
}
process.exit(0);
