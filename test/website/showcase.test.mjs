import { test } from 'node:test';
import assert from 'node:assert/strict';
import { sceneMarkup, placeholderScenes } from '../../website/assets/js/showcase.js';

const video = {
  id: 'themes',
  title: 'Themes',
  webm: 'themes.webm',
  mp4: 'themes.mp4',
  poster: 'themes.jpg',
  shots: [],
};

test('a video scene plays muted, looped, with both sources and a poster', () => {
  const html = sceneMarkup(video, { reducedMotion: false });
  assert.match(html, /<video[^>]*\bmuted\b/);
  assert.match(html, /<video[^>]*\bloop\b/);
  assert.match(html, /<video[^>]*\bplaysinline\b/);
  assert.match(html, /<video[^>]*\bautoplay\b/);
  assert.match(html, /poster="media\/showcase\/themes\.jpg"/);
  assert.match(html, /<source src="media\/showcase\/themes\.webm" type="video\/webm">/);
  assert.match(html, /<source src="media\/showcase\/themes\.mp4" type="video\/mp4">/);
});

test('reduced motion: no autoplay, the poster shows', () => {
  const html = sceneMarkup(video, { reducedMotion: true });
  assert.doesNotMatch(html, /autoplay/);
  assert.match(html, /poster="media\/showcase\/themes\.jpg"/);
});

test('a scene with only screenshots shows each one', () => {
  const html = sceneMarkup(
    { id: 'search', title: 'Search', shots: ['search-1.webp', 'search-2.webp'] },
    { reducedMotion: false },
  );
  assert.doesNotMatch(html, /<video/);
  assert.equal(html.match(/<img /g).length, 2);
  assert.match(html, /src="media\/showcase\/search-1\.webp"/);
  assert.match(html, /alt="Search in Songies, screenshot 1 of 2"/);
});

test('placeholders cover the four topics in order', () => {
  assert.deepEqual(
    placeholderScenes().map((s) => s.title),
    ['Themes', 'Playlists & covers', 'Downloads', 'Search'],
  );
});

test('several screenshots come with a dot to pick each one', () => {
  const html = sceneMarkup(
    { id: 'search', title: 'Search', shots: ['a.webp', 'b.webp', 'c.webp'] },
    { reducedMotion: false },
  );
  assert.equal(html.match(/<button[^>]*data-shot=/g).length, 3);
  assert.match(html, /aria-label="Screenshot 2 of 3"/);
  // The first one shows to begin with.
  assert.match(html, /<img class="shot is-shown"[^>]*a\.webp/);
});

test('a single screenshot has no dots', () => {
  const html = sceneMarkup({ id: 'x', title: 'X', shots: ['a.webp'] }, { reducedMotion: false });
  assert.doesNotMatch(html, /data-shot=/);
});

test('titles are escaped', () => {
  const html = sceneMarkup({ id: 'x', title: '<b>', shots: ['a.webp'] }, { reducedMotion: false });
  assert.doesNotMatch(html, /<b>/);
});
