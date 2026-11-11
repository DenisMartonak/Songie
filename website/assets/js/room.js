// Room links: /Songie/r/<CODE> → songies://room/<CODE>.
// Same rules as the app (lib/room/room_links.dart).

const ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

function cleanCode(s) {
  const c = s.replace(/[\s-]/g, '').toUpperCase();
  if (c.length !== 8) return null;
  for (const ch of c) if (!ALPHABET.includes(ch)) return null;
  return c;
}

/** The room code in a path ending in /r/<code>, or null. */
export function roomCodeFromPath(pathname) {
  let segs;
  try {
    segs = (pathname || '').split('/').filter(Boolean).map(decodeURIComponent);
  } catch {
    return null; // a malformed %-escape
  }
  if (segs.length < 2 || segs[segs.length - 2] !== 'r') return null;
  return cleanCode(segs[segs.length - 1]);
}

/** `ABCD2345` shown as `ABCD-2345`. */
export const formatRoomCode = (code) =>
  code.length === 8 ? `${code.slice(0, 4)}-${code.slice(4)}` : code;

/** The address that opens Songies at the room. */
export const appLink = (code) => `songies://room/${code}`;
