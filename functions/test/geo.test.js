const test = require('node:test');
const assert = require('node:assert/strict');
const { coarse, geohash, band, kmBetween, publicPoint, publicKm, isoCountry } = require('../lib/geo');
const { parseWav, parseMp4, sniff, limitsFor } = require('../lib/media');

test('coarse point is about 100m', () => {
  assert.equal(coarse(12.971612), 12.972);
  assert.equal(coarse(77.594566), 77.595);
});

test('same place stays in one geohash cell', () => {
  const a = geohash(coarse(12.9716), coarse(77.5946), 4);
  const b = geohash(coarse(12.9719), coarse(77.5942), 4);
  assert.equal(a, b);
  assert.equal(a.length, 4);
});

test('public point stays on a 2 km grid', () => {
  const point = publicPoint(12.9716, 77.5946);
  assert.equal(point.lat, 12.98);
  assert.equal(point.lng, 77.6);
  const near = publicPoint(12.975, 77.595);
  assert.equal(near.lat, point.lat);
  assert.equal(near.lng, point.lng);
});

test('public km is at least 2', () => {
  assert.equal(publicKm(0.4), 2);
  assert.equal(publicKm(2.4), 2);
  assert.equal(publicKm(14.6), 15);
  assert.equal(band(publicKm(0.4)), 'mid');
});

test('country comes from the post coordinates', () => {
  assert.equal(isoCountry(28.6139, 77.209), 'IN');
  assert.equal(isoCountry(51.5074, -0.1278), 'GB');
  assert.equal(isoCountry(0, -140), null);
});

test('distance bands', () => {
  assert.equal(band(0.4), 'near');
  assert.equal(band(8), 'mid');
  assert.equal(band(40), 'far');
  const d = kmBetween(12.97, 77.59, 12.98, 77.59);
  assert.ok(d < 2);
});

test('wav duration and magic', () => {
  const data = Buffer.alloc(16000);
  const header = Buffer.alloc(44);
  header.write('RIFF', 0);
  header.writeUInt32LE(36 + data.length, 4);
  header.write('WAVE', 8);
  header.write('fmt ', 12);
  header.writeUInt32LE(16, 16);
  header.writeUInt16LE(1, 20);
  header.writeUInt16LE(1, 22);
  header.writeUInt32LE(8000, 24);
  header.writeUInt32LE(8000, 28);
  header.writeUInt16LE(1, 32);
  header.writeUInt16LE(8, 34);
  header.write('data', 36);
  header.writeUInt32LE(data.length, 40);
  const wav = Buffer.concat([header, data]);
  assert.equal(sniff(wav), 'wav');
  const info = parseWav(wav);
  assert.ok(Math.abs(info.duration - 2) < 0.01);
  assert.equal(limitsFor('audio', info), null);
  assert.equal(limitsFor('audio', { duration: 90, tracks: 1 }), 'duration');
});

test('mp4 header duration and size cap', () => {
  function box(type, payload) {
    const head = Buffer.alloc(8);
    head.writeUInt32BE(8 + payload.length, 0);
    head.write(type, 4);
    return Buffer.concat([head, payload]);
  }
  const ftyp = box('ftyp', Buffer.from('isom'));
  const mvhd = Buffer.alloc(20);
  mvhd[0] = 0;
  mvhd.writeUInt32BE(1000, 12);
  mvhd.writeUInt32BE(20000, 16);
  const tkhd = Buffer.alloc(84);
  tkhd[0] = 0;
  tkhd.writeUInt32BE(1280 * 65536, 76);
  tkhd.writeUInt32BE(720 * 65536, 80);
  const trak = box('trak', box('tkhd', tkhd));
  const moov = box('moov', Buffer.concat([box('mvhd', mvhd), trak]));
  const buf = Buffer.concat([ftyp, moov]);
  const info = parseMp4(buf);
  assert.equal(info.duration, 20);
  assert.equal(info.width, 1280);
  assert.equal(info.height, 720);
  assert.equal(limitsFor('video', info), null);
  assert.equal(limitsFor('video', { duration: 20, width: 1920, height: 1080, tracks: 1 }), 'dimensions');
});

test('jpeg magic is not html', () => {
  assert.equal(sniff(Buffer.from([0xff, 0xd8, 0xff, 0xe0])), 'jpeg');
  assert.equal(sniff(Buffer.from('<svg></svg>')), null);
});
