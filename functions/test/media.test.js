const test = require('node:test');
const assert = require('node:assert');
const { extFor, publicUrl } = require('../lib/media');

test('media extensions match the upload kind', () => {
  assert.equal(extFor('image', 'image/webp'), 'webp');
  assert.equal(extFor('audio', 'audio/mp4'), 'm4a');
  assert.equal(extFor('video', 'video/mp4'), 'mp4');
  assert.equal(extFor('image', 'video/mp4'), null);
});

test('download url stays stable for the same token', () => {
  const url = publicUrl('worky-93fbc.firebasestorage.app', 'users/a/b.webp', 'tok');
  assert.equal(
    url,
    'https://firebasestorage.googleapis.com/v0/b/worky-93fbc.firebasestorage.app/o/users%2Fa%2Fb.webp?alt=media&token=tok',
  );
});
