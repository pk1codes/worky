const test = require('node:test');
const assert = require('node:assert');
const { extFor, publicUrl, needsThumb, limitsFor } = require('../lib/media');

test('media extensions match the upload kind', () => {
  assert.equal(extFor('image', 'image/webp'), 'webp');
  assert.equal(extFor('audio', 'audio/mp4'), 'm4a');
  assert.equal(extFor('video', 'video/mp4'), 'mp4');
  assert.equal(extFor('image', 'video/mp4'), null);
  assert.equal(extFor('audio', 'audio/wav'), null);
  assert.equal(extFor('voice', 'audio/mp4'), 'm4a');
  assert.equal(extFor('voice', 'audio/mpeg'), null);
});

test('a voice note cannot run past a minute', () => {
  assert.equal(limitsFor('voice', { duration: 60, tracks: 1 }), null);
  assert.equal(limitsFor('voice', { duration: 61, tracks: 1 }), 'duration');
});

test('thumbs are only for images larger than the strip', () => {
  assert.equal(needsThumb(481, 100), true);
  assert.equal(needsThumb(100, 481), true);
  assert.equal(needsThumb(480, 480), false);
  assert.equal(needsThumb(0, 0), false);
});

test('download url stays stable for the same token', () => {
  const url = publicUrl('worky-93fbc.firebasestorage.app', 'users/a/b.webp', 'tok');
  assert.equal(
    url,
    'https://firebasestorage.googleapis.com/v0/b/worky-93fbc.firebasestorage.app/o/users%2Fa%2Fb.webp?alt=media&token=tok',
  );
});
