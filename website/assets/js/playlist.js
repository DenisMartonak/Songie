// Shared playlist links: /Songie/p/<CODE> → songies://playlist/<CODE>.
// Same rules as the app (lib/playlists/playlist_links.dart).

const ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

function cleanCode(s) {
  const c = s.trim().toUpperCase();
  if (c.length !== 12) return null;
  for (const ch of c) if (!ALPHABET.includes(ch)) return null;
  return c;
}

/** The playlist code in a path ending in /p/<code>, or null. */
export function playlistCodeFromPath(pathname) {
  let segs;
  try {
    segs = (pathname || '').split('/').filter(Boolean).map(decodeURIComponent);
  } catch {
    return null; // a malformed %-escape
  }
  if (segs.length < 2 || segs[segs.length - 2] !== 'p') return null;
  return cleanCode(segs[segs.length - 1]);
}

/** The address that opens Songies at the shared playlist. */
export const playlistAppLink = (code) => `songies://playlist/${code}`;
