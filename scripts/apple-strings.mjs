/**
 * Words the Apple TV app types in its own source instead of reading from the catalogue
 * (packages/i18n). The channel must say the same words, so each is listed here under an `apple.`
 * id with the file it is in; `generate.mjs` fails when the file no longer contains the text, and
 * writes it into every locale's translations (the Apple app shows these in US English everywhere,
 * as it has no regional form for them).
 */
const auth = 'apps/native/src/screens/auth';
const app = 'apps/native/src/app';

export const appleStrings = {
  'apple.connect.unreachable': {text: 'Portico couldn’t reach that server. Check the address and try again.', file: `${app}/direct-connect.ts`},
  'apple.connect.changed': {text: 'The server changed while you were signing in. Try again.', file: `${app}/direct-connect.ts`},
  'apple.connect.setupRequired': {text: 'This server hasn’t finished setup. Complete setup in a web browser first.', file: `${app}/direct-connect.ts`},
  'apple.activation.failed': {text: 'Portico couldn’t get a sign-in code. Check your connection, then get a new code.', file: `${auth}/Activation.tsx`},
  'apple.direct.addressLead': {text: 'Enter your server’s address. Then approve this TV from a phone or computer that’s already signed in — no password to type.', file: `${auth}/DirectSignIn.tsx`},
  'apple.direct.passwordLead': {text: 'Use an account that lives on your server. It stays between this device and that server.', file: `${auth}/DirectSignIn.tsx`},
  'apple.direct.addressExample': {text: '192.168.1.20:32500', file: `${auth}/DirectSignIn.tsx`},
  'apple.direct.usernameExample': {text: 'name@example.com', file: `${auth}/DirectSignIn.tsx`},
  'apple.activation.defaultHost': {text: 'web.getportico.tv/device', file: `${auth}/Activation.tsx`},
  'apple.together.hostPlays': {text: 'Only the host can play and pause for the group.', file: `${app}/together.tsx`},
  'apple.together.hostMoves': {text: 'Only the host can move the group to another moment.', file: `${app}/together.tsx`},
};
