import { test } from 'node:test';
import assert from 'node:assert/strict';
import { playlistCodeFromPath, playlistAppLink } from '../../website/assets/js/playlist.js';

test('playlistCodeFromPath reads the code', () => {
  assert.equal(playlistCodeFromPath('/Songie/p/ABCDEFGH2345'), 'ABCDEFGH2345');
  assert.equal(playlistCodeFromPath('/Songie/p/abcdefgh2345/'), 'ABCDEFGH2345');
  assert.equal(playlistCodeFromPath('/p/ABCDEFGH2345'), 'ABCDEFGH2345');
});

test('playlistCodeFromPath rejects bad codes, room links and other paths', () => {
  assert.equal(playlistCodeFromPath('/Songie/p/ABCDEFGH234I'), null);
  assert.equal(playlistCodeFromPath('/Songie/p/ABCD2345'), null);
  assert.equal(playlistCodeFromPath('/Songie/r/ABCDEFGH2345'), null);
  assert.equal(playlistCodeFromPath('/Songie/p/ABCDEFGH2345/extra'), null);
  assert.equal(playlistCodeFromPath('/Songie/p/%E0%A4%A'), null);
});

test('playlistAppLink opens the app at the playlist', () => {
  assert.equal(playlistAppLink('ABCDEFGH2345'), 'songies://playlist/ABCDEFGH2345');
});
