const test = require('node:test');
const assert = require('node:assert');
const { extFor, publicUrl, needsThumb, limitsFor, clipMp4, parseMp4 } = require('../lib/media');

test('media extensions match the upload kind', () => {
  assert.equal(extFor('image', 'image/webp'), 'webp');
  assert.equal(extFor('audio', 'audio/mp4'), 'm4a');
  assert.equal(extFor('video', 'video/mp4'), 'mp4');
  assert.equal(extFor('image', 'video/mp4'), null);
  assert.equal(extFor('audio', 'audio/wav'), null);
  assert.equal(extFor('voice', 'audio/mp4'), null);
});

test('audio cannot run past a minute', () => {
  assert.equal(limitsFor('audio', { duration: 60, tracks: 1 }), null);
  assert.equal(limitsFor('audio', { duration: 61, tracks: 1 }), 'duration');
});

test('thumbs are only for images larger than the strip', () => {
  assert.equal(needsThumb(481, 100), true);
  assert.equal(needsThumb(100, 481), true);
  assert.equal(needsThumb(480, 480), false);
  assert.equal(needsThumb(0, 0), false);
});

test('video check reads ftyp and moov and skips mdat', async () => {
  function box(type, payload) {
    const head = Buffer.alloc(8);
    head.writeUInt32BE(8 + payload.length, 0);
    head.write(type, 4);
    return Buffer.concat([head, payload]);
  }
  const ftyp = box('ftyp', Buffer.from('isom'));
  const mdat = box('mdat', Buffer.alloc(50_000, 1));
  const mvhd = Buffer.alloc(20);
  mvhd.writeUInt32BE(1000, 12);
  mvhd.writeUInt32BE(5000, 16);
  const moov = box('moov', box('mvhd', mvhd));
  const file = Buffer.concat([ftyp, mdat, moov]);
  const reads = [];
  const clip = await clipMp4(file.length, async (start, end) => {
    reads.push([start, end]);
    return file.subarray(start, end + 1);
  });
  const info = parseMp4(clip);
  assert.equal(info.duration, 5);
  const pulled = reads.reduce((sum, [start, end]) => sum + (end - start + 1), 0);
  assert.ok(pulled < 10_000);
});

test('download url stays stable for the same token', () => {
  const url = publicUrl('worky-93fbc.firebasestorage.app', 'users/a/b.webp', 'tok');
  assert.equal(
    url,
    'https://firebasestorage.googleapis.com/v0/b/worky-93fbc.firebasestorage.app/o/users%2Fa%2Fb.webp?alt=media&token=tok',
  );
});
