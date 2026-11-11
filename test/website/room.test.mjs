import { test } from 'node:test';
import assert from 'node:assert/strict';
import { roomCodeFromPath, formatRoomCode, appLink } from '../../website/assets/js/room.js';

test('roomCodeFromPath reads the code', () => {
  assert.equal(roomCodeFromPath('/Songie/r/ABCD2345'), 'ABCD2345');
  assert.equal(roomCodeFromPath('/Songie/r/abcd-2345/'), 'ABCD2345');
  assert.equal(roomCodeFromPath('/r/ABCD2345'), 'ABCD2345');
});

test('roomCodeFromPath rejects bad codes and other paths', () => {
  assert.equal(roomCodeFromPath('/Songie/r/ABCD234I'), null); // I is not in the alphabet
  assert.equal(roomCodeFromPath('/Songie/r/ABC'), null);
  assert.equal(roomCodeFromPath('/Songie/r/'), null);
  assert.equal(roomCodeFromPath('/Songie/x/ABCD2345'), null);
  assert.equal(roomCodeFromPath('/Songie/r/ABCD2345/extra'), null);
  assert.equal(roomCodeFromPath('/Songie/'), null);
  assert.equal(roomCodeFromPath('/Songie/r/%E0%A4%A'), null); // malformed escape
});

test('formatRoomCode and appLink', () => {
  assert.equal(formatRoomCode('ABCD2345'), 'ABCD-2345');
  assert.equal(appLink('ABCD2345'), 'songies://room/ABCD2345');
});

test('shouldAutoOpen: once per tab, only where Songies exists', async () => {
  const { shouldAutoOpen } = await import('../../website/assets/js/room.js');
  assert.equal(shouldAutoOpen('linux', false), true);
  assert.equal(shouldAutoOpen('android', false), true);
  assert.equal(shouldAutoOpen('windows', true), false); // came back with Back
  assert.equal(shouldAutoOpen(null, false), false); // iPhone, Mac: no app to open
});
