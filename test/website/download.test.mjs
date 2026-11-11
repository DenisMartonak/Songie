import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  detectPlatform,
  pickDownload,
  RELEASES_URL,
  LATEST_API,
} from '../../website/assets/js/download.js';

const UA = {
  pixel:
    'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36',
  windows:
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36 Edg/130.0.0.0',
  fedora:
    'Mozilla/5.0 (X11; Linux x86_64; rv:132.0) Gecko/20100101 Firefox/132.0',
  iphone:
    'Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.1 Mobile/15E148 Safari/604.1',
  mac: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.1 Safari/605.1.15',
};

const base = 'https://github.com/DenisMartonak/Songie/releases/download/v1.4.0';
const asset = (name) => ({ name, browser_download_url: `${base}/${name}` });
const release = {
  assets: [
    asset('SHA256SUMS'),
    asset('songies-1.4.0-windows-setup.exe'),
    asset('songies-1.4.0-x86_64.AppImage'),
    asset('songies-1.4.0.apk'),
    asset('version.json'),
  ],
};

test('constants point at the Songie repo', () => {
  assert.equal(RELEASES_URL, 'https://github.com/DenisMartonak/Songie/releases/latest');
  assert.equal(LATEST_API, 'https://api.github.com/repos/DenisMartonak/Songie/releases/latest');
});

test('detectPlatform: Android before Linux', () => {
  assert.equal(detectPlatform(UA.pixel), 'android');
});

test('detectPlatform: Windows and desktop Linux', () => {
  assert.equal(detectPlatform(UA.windows), 'windows');
  assert.equal(detectPlatform(UA.fedora), 'linux');
});

test('detectPlatform: Apple and unknown devices get null', () => {
  assert.equal(detectPlatform(UA.iphone), null);
  assert.equal(detectPlatform(UA.mac), null);
  assert.equal(detectPlatform(''), null);
});

test('pickDownload: the matching asset for each platform', () => {
  assert.deepEqual(pickDownload('android', release), {
    label: 'Download for Android',
    url: `${base}/songies-1.4.0.apk`,
  });
  assert.deepEqual(pickDownload('windows', release), {
    label: 'Download for Windows',
    url: `${base}/songies-1.4.0-windows-setup.exe`,
  });
  assert.deepEqual(pickDownload('linux', release), {
    label: 'Download for Linux',
    url: `${base}/songies-1.4.0-x86_64.AppImage`,
  });
});

test('pickDownload: falls back to all downloads', () => {
  const all = { label: 'All downloads', url: RELEASES_URL };
  assert.deepEqual(pickDownload('windows', null), all);
  assert.deepEqual(
    pickDownload('linux', { assets: release.assets.filter((a) => !a.name.endsWith('.AppImage')) }),
    all,
  );
  assert.deepEqual(pickDownload(null, release), all);
  assert.deepEqual(pickDownload('android', { message: 'API rate limit exceeded' }), all);
});
