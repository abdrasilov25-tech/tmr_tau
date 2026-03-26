import fs from 'fs';
import { importPKCS8, SignJWT } from 'jose';

const p8Path = process.env.APPLE_P8_PATH ?? './apple_key.p8';

const TEAM_ID = process.env.APPLE_TEAM_ID ?? '';
const KEY_ID = process.env.APPLE_KEY_ID ?? '';
// SERVICE_ID / CLIENT_ID для Sign in with Apple (его же обычно используете как sub)
const CLIENT_ID = process.env.APPLE_CLIENT_ID ?? '';

if (!TEAM_ID || !KEY_ID || !CLIENT_ID) {
  console.error('Missing env vars. Set:');
  console.error('  APPLE_TEAM_ID, APPLE_KEY_ID, APPLE_CLIENT_ID');
  console.error(`Optional: APPLE_P8_PATH (default: ${p8Path})`);
  process.exit(1);
}

const privateKeyPem = fs.readFileSync(p8Path, 'utf8');
const privateKey = await importPKCS8(privateKeyPem, 'ES256');

const now = Math.floor(Date.now() / 1000);
const exp = now + 60 * 60 * 24 * 180; // ~180 дней

const jwt = await new SignJWT({})
  .setProtectedHeader({ alg: 'ES256', kid: KEY_ID })
  .setIssuer(TEAM_ID)
  .setSubject(CLIENT_ID)
  .setAudience('https://appleid.apple.com')
  .setIssuedAt(now)
  .setExpirationTime(exp)
  .sign(privateKey);

console.log(jwt);

