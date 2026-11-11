// The Download button: the right installer for this device from the latest
// GitHub release, or the releases page when that can't be worked out.

export const RELEASES_URL = 'https://github.com/DenisMartonak/Songie/releases/latest';
export const LATEST_API = 'https://api.github.com/repos/DenisMartonak/Songie/releases/latest';

const PLATFORMS = {
  android: { label: 'Download for Android', suffix: '.apk' },
  windows: { label: 'Download for Windows', suffix: '-windows-setup.exe' },
  linux: { label: 'Download for Linux', suffix: '-x86_64.AppImage' },
};

/** 'android' | 'windows' | 'linux' | null (Apple devices and anything else). */
export function detectPlatform(userAgent) {
  const ua = userAgent || '';
  // Android user agents also say "Linux", so Android goes first.
  if (/Android/i.test(ua)) return 'android';
  if (/iPhone|iPad|iPod|Macintosh|CrOS/i.test(ua)) return null;
  if (/Windows/i.test(ua)) return 'windows';
  if (/Linux|X11/i.test(ua)) return 'linux';
  return null;
}

/** The label and link for [platform] in [release] (GitHub API JSON or null). */
export function pickDownload(platform, release) {
  const p = PLATFORMS[platform];
  const assets = Array.isArray(release?.assets) ? release.assets : [];
  const asset = p && assets.find((a) => typeof a?.name === 'string' && a.name.endsWith(p.suffix));
  if (!asset?.browser_download_url) return { label: 'All downloads', url: RELEASES_URL };
  return { label: p.label, url: asset.browser_download_url };
}

function apply(links, { label, url }) {
  for (const a of links) {
    a.href = url;
    const text = a.querySelector('[data-download-label]') ?? a;
    text.textContent = label;
  }
}

/** Points every [selector] link at this device's installer. Never throws. */
export async function upgradeDownloadLinks(selector = '[data-download]') {
  try {
    const links = [...document.querySelectorAll(selector)];
    if (!links.length) return;
    const platform = detectPlatform(navigator.userAgent);
    apply(links, pickDownload(null, null));
    if (!platform) return;
    const ctrl = new AbortController();
    const timer = setTimeout(() => ctrl.abort(), 5000);
    try {
      const res = await fetch(LATEST_API, {
        signal: ctrl.signal,
        headers: { Accept: 'application/vnd.github+json' },
      });
      if (res.ok) apply(links, pickDownload(platform, await res.json()));
    } finally {
      clearTimeout(timer);
    }
  } catch {
    // Offline, rate-limited or blocked: the "All downloads" link stays.
  }
}
