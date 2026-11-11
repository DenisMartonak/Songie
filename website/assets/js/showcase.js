// The showcase under the hero: one screen frame and a tab per topic.
// Clips come from media/showcase/showcase.json (written by tool/showcase.sh);
// without it each topic shows a placeholder.

const MEDIA = 'media/showcase/';

const TOPICS = [
  { id: 'themes', title: 'Themes', caption: 'Pick a theme, make your own, or let the colours follow the album cover.' },
  { id: 'playlists', title: 'Playlists & covers', caption: 'Make playlists and give each one a cover of your own.' },
  { id: 'downloads', title: 'Downloads', caption: 'Download songs and whole playlists to listen offline.' },
  { id: 'search', title: 'Search', caption: 'Search your library and YouTube Music together.' },
];

const esc = (s) =>
  String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);

/** The four topics with no media yet. */
export const placeholderScenes = () => TOPICS.map((t) => ({ ...t, shots: [] }));

/** The frame's content for one scene. */
export function sceneMarkup(scene, { reducedMotion }) {
  const title = esc(scene.title);
  if (scene.webm || scene.mp4) {
    const poster = scene.poster ? ` poster="${MEDIA}${esc(scene.poster)}"` : '';
    const sources = [
      scene.webm && `<source src="${MEDIA}${esc(scene.webm)}" type="video/webm">`,
      scene.mp4 && `<source src="${MEDIA}${esc(scene.mp4)}" type="video/mp4">`,
    ].filter(Boolean).join('');
    const play = reducedMotion ? ' controls' : ' autoplay';
    return `<video class="shot" muted loop playsinline preload="metadata"${play}${poster} aria-label="${title} in Songies">${sources}</video>`;
  }
  const shots = scene.shots ?? [];
  if (shots.length) {
    return `<div class="shots shots-${shots.length}">${shots
      .map((s, i) => `<img class="shot" src="${MEDIA}${esc(s)}" alt="${title} in Songies, screenshot ${i + 1} of ${shots.length}" loading="lazy">`)
      .join('')}</div>`;
  }
  return `<div class="shot-placeholder"><span>${title}</span></div>`;
}

/** Topics in their fixed order, with media from the manifest where it has some. */
export function mergeScenes(manifest) {
  const byId = new Map((manifest?.scenes ?? []).map((s) => [s.id, s]));
  return placeholderScenes().map((t) => ({ ...t, ...(byId.get(t.id) ?? {}), title: t.title, caption: t.caption }));
}

/** Builds the tabs and frame inside [root] (browser only). */
export async function renderShowcase(root) {
  let manifest = null;
  try {
    const res = await fetch(`${MEDIA}showcase.json`, { cache: 'no-cache' });
    if (res.ok) manifest = await res.json();
  } catch {
    // No clips yet: placeholders.
  }
  const scenes = mergeScenes(manifest);
  const reducedMotion = matchMedia('(prefers-reduced-motion: reduce)').matches;
  const frame = root.querySelector('[data-frame]');
  const caption = root.querySelector('[data-caption]');
  const tabs = root.querySelector('[data-tabs]');
  tabs.innerHTML = scenes
    .map((s, i) => `<button type="button" role="tab" id="tab-${s.id}" aria-controls="showcase-frame" aria-selected="${i === 0}" tabindex="${i === 0 ? 0 : -1}">${esc(s.title)}</button>`)
    .join('');
  const buttons = [...tabs.querySelectorAll('[role=tab]')];
  const show = (i) => {
    buttons.forEach((b, j) => {
      b.setAttribute('aria-selected', String(i === j));
      b.tabIndex = i === j ? 0 : -1;
    });
    frame.setAttribute('aria-labelledby', buttons[i].id);
    frame.innerHTML = sceneMarkup(scenes[i], { reducedMotion });
    caption.textContent = scenes[i].caption;
  };
  buttons.forEach((b, i) => {
    b.addEventListener('click', () => show(i));
    b.addEventListener('keydown', (e) => {
      const d = e.key === 'ArrowRight' ? 1 : e.key === 'ArrowLeft' ? -1 : 0;
      if (!d) return;
      const n = (i + d + buttons.length) % buttons.length;
      buttons[n].focus();
      show(n);
    });
  });
  show(0);
}
