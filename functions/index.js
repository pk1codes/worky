const crypto = require('crypto');
const admin = require('firebase-admin');
const { onRequest } = require('firebase-functions/v2/https');
const { defineSecret } = require('firebase-functions/params');
const sharp = require('sharp');
const { LANGS, coarse, geohash, ring, hashBounds, kmBetween, band, daysAgo, publicPoint, publicKm, isoCountry } = require('./lib/geo');
const { shelfId, shelfCard, packShelf, wantNeighbor, capBlocks } = require('./lib/shelf');
const { categoryTrail } = require('./lib/categories');
const { parseMp4, parseWav, parseMp3, sniff, KIND_TYPE, SERVE_TYPE, limitsFor, extFor, clipMp4, publicUrl, THUMB_EDGE, needsThumb } = require('./lib/media');
const { allow, clientIp, overCap } = require('./lib/gate');

admin.initializeApp({
  projectId: 'worky-93fbc',
  storageBucket: 'worky-93fbc.firebasestorage.app',
});

const db = admin.firestore();
const bucket = admin.storage().bucket();
const SHELF_MS = 30 * 60 * 1000;
const CATALOG_MS = 60 * 60 * 1000;
const shelfMem = new Map();
let catalog = null;
let catalogAt = 0;

function dropShelfCache(ids) {
  for (const id of ids) shelfMem.delete(id);
}

function dropCatalog() {
  catalog = null;
  catalogAt = 0;
}
const fileTokenKey = defineSecret('FILE_TOKEN_KEY');

function fileKey() {
  return process.env.FILE_TOKEN_KEY || 'worky-local-file-key';
}
const MAX_BYTES = { image: 8_000_000, video: 20_000_000, audio: 8_000_000 };

const NAMES = {
  cook: { en: 'Cook' },
  'car-driver': { en: 'Car driver' },
  'house-maid': { en: 'House Maid' },
  'security-guard': { en: 'Security Guard' },
  'delivery-driver': { en: 'Delivery Driver' },
  'sales-man': { en: 'Sales Man' },
  'car-cleaner': { en: 'Car cleaner' },
  loader: { en: 'Loader' },
  'oil-field-rigs': { en: 'Oil Field Rigs' },
  hospital: { en: 'Hospital' },
  'oil-refineries': { en: 'Oil Refineries' },
  'asst-driller': { en: 'Asst Driller' },
  driller: { en: 'Driller' },
  medic: { en: 'Medic' },
  'service-companies': { en: 'Service Companies Jobs' },
  'oil-company-jobs': { en: 'Oil Company Jobs' },
  'staff-nurse': { en: 'Staff Nurse' },
  anm: { en: 'ANM' },
  'ward-boy': { en: 'Ward Boy' },
  ayah: { en: 'Ayah' },
  housekeeping: { en: 'Housekeeping' },
  'lab-technician': { en: 'Lab Technician' },
  pharmacist: { en: 'Pharmacist' },
  'plant-helper': { en: 'Plant Helper' },
  fitter: { en: 'Fitter' },
  welder: { en: 'Welder' },
  rigger: { en: 'Rigger' },
  scaffolder: { en: 'Scaffolder' },
  electrician: { en: 'Electrician' },
  'process-operator': { en: 'Process Operator' },
};

const SEED = [
  { id: 'cook', parentId: '', sort: 0, color: '#C2410C', kind: 'job' },
  { id: 'car-driver', parentId: '', sort: 1, color: '#1D4ED8', kind: 'job' },
  { id: 'house-maid', parentId: '', sort: 2, color: '#7C3AED', kind: 'job' },
  { id: 'security-guard', parentId: '', sort: 3, color: '#0F766E', kind: 'job' },
  { id: 'delivery-driver', parentId: '', sort: 4, color: '#B45309', kind: 'job' },
  { id: 'sales-man', parentId: '', sort: 5, color: '#BE123C', kind: 'job' },
  { id: 'car-cleaner', parentId: '', sort: 6, color: '#0369A1', kind: 'job' },
  { id: 'loader', parentId: '', sort: 7, color: '#3F6212', kind: 'job' },
  { id: 'oil-field-rigs', parentId: '', sort: 8, color: '#44403C', kind: 'parent' },
  { id: 'hospital', parentId: '', sort: 9, color: '#0E7490', kind: 'parent' },
  { id: 'oil-refineries', parentId: '', sort: 10, color: '#92400E', kind: 'parent' },
  { id: 'asst-driller', parentId: 'oil-field-rigs', sort: 0, color: '#9A3412', kind: 'job' },
  { id: 'driller', parentId: 'oil-field-rigs', sort: 1, color: '#7F1D1D', kind: 'job' },
  { id: 'medic', parentId: 'oil-field-rigs', sort: 2, color: '#155E75', kind: 'job' },
  { id: 'service-companies', parentId: 'oil-field-rigs', sort: 3, color: '#365314', kind: 'parent' },
  { id: 'oil-company-jobs', parentId: 'oil-field-rigs', sort: 4, color: '#1E3A8A', kind: 'parent' },
  { id: 'staff-nurse', parentId: 'hospital', sort: 0, color: '#0F766E', kind: 'job' },
  { id: 'anm', parentId: 'hospital', sort: 1, color: '#155E75', kind: 'job' },
  { id: 'ward-boy', parentId: 'hospital', sort: 2, color: '#1D4ED8', kind: 'job' },
  { id: 'ayah', parentId: 'hospital', sort: 3, color: '#7C3AED', kind: 'job' },
  { id: 'housekeeping', parentId: 'hospital', sort: 4, color: '#0369A1', kind: 'job' },
  { id: 'lab-technician', parentId: 'hospital', sort: 5, color: '#0E7490', kind: 'job' },
  { id: 'pharmacist', parentId: 'hospital', sort: 6, color: '#BE123C', kind: 'job' },
  { id: 'plant-helper', parentId: 'oil-refineries', sort: 0, color: '#3F6212', kind: 'job' },
  { id: 'fitter', parentId: 'oil-refineries', sort: 1, color: '#9A3412', kind: 'job' },
  { id: 'welder', parentId: 'oil-refineries', sort: 2, color: '#7F1D1D', kind: 'job' },
  { id: 'rigger', parentId: 'oil-refineries', sort: 3, color: '#57534E', kind: 'job' },
  { id: 'scaffolder', parentId: 'oil-refineries', sort: 4, color: '#1E3A8A', kind: 'job' },
  { id: 'electrician', parentId: 'oil-refineries', sort: 5, color: '#B45309', kind: 'job' },
  { id: 'process-operator', parentId: 'oil-refineries', sort: 6, color: '#365314', kind: 'job' },
];

function tokenFor(id, ms = 3600_000) {
  const exp = Date.now() + ms;
  const sig = crypto.createHmac('sha256', fileKey()).update(`${id}.${exp}`).digest('base64url');
  return `${exp}.${sig}`;
}

function tokenOk(id, token) {
  const parts = String(token || '').split('.');
  if (parts.length !== 2) return false;
  const [exp, sig] = parts;
  if (!/^\d+$/.test(exp) || Number(exp) < Date.now()) return false;
  const expect = crypto.createHmac('sha256', fileKey()).update(`${id}.${exp}`).digest('base64url');
  const a = Buffer.from(sig);
  const b = Buffer.from(expect);
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

function apiRoot(req) {
  if (process.env.FUNCTIONS_EMULATOR === 'true') {
    return `http://${req.get('host')}/worky-93fbc/us-central1/api`;
  }
  return 'https://us-central1-worky-93fbc.cloudfunctions.net/api';
}

function fileUrl(req, id) {
  return `${apiRoot(req)}/v1/files/${encodeURIComponent(id)}?t=${tokenFor(id)}`;
}

function pathOf(req) {
  const raw = (req.originalUrl || req.url || '/').split('?')[0];
  const idx = raw.indexOf('/v1/');
  return idx >= 0 ? raw.slice(idx) : raw;
}

function send(res, status, body) {
  res.status(status).json(body);
}

function pairCoord(body) {
  const hasLat = body != null && body.lat != null;
  const hasLng = body != null && body.lng != null;
  if (!hasLat && !hasLng) return { ok: true };
  const { lat, lng } = body;
  const latOk = typeof lat === 'number' && Number.isFinite(lat) && lat >= -90 && lat <= 90;
  const lngOk = typeof lng === 'number' && Number.isFinite(lng) && lng >= -180 && lng <= 180;
  if (!latOk || !lngOk) return { ok: false };
  return { ok: true, lat, lng };
}

async function authed(req, res) {
  if (process.env.FUNCTIONS_EMULATOR !== 'true') {
    const appCheck = req.get('x-firebase-appcheck');
    if (!appCheck) {
      send(res, 401, { error: 'try_again' });
      return null;
    }
    try {
      await admin.appCheck().verifyToken(appCheck);
    } catch (_) {
      send(res, 401, { error: 'try_again' });
      return null;
    }
  }
  const header = req.get('authorization') || '';
  const match = header.match(/^Bearer (.+)$/i);
  if (!match) {
    send(res, 401, { error: 'try_again' });
    return null;
  }
  try {
    return await admin.auth().verifyIdToken(match[1]);
  } catch (_) {
    send(res, 401, { error: 'try_again' });
    return null;
  }
}

function pace(key, max, windowMs) {
  const hit = allow(key, max, windowMs);
  return hit.ok ? 0 : hit.retryAfter;
}

function tooFast(res, retryAfter) {
  res.set('Retry-After', String(retryAfter || 1));
  send(res, 429, { error: 'try_again' });
}

function fail(res, status, retryAfter) {
  if (status === 429) {
    tooFast(res, retryAfter);
    return;
  }
  send(res, status, { error: 'try_again' });
}

async function alreadyOver(key, max) {
  const snap = await db.collection('limits').doc(key).get();
  if (!snap.exists) return 0;
  const now = Date.now();
  const reset = snap.get('reset') || 0;
  if (!overCap(snap.get('n') || 0, reset, now, max)) return 0;
  return Math.max(1, Math.ceil((reset - now) / 1000));
}

async function limited(key, max, windowMs) {
  const ref = db.collection('limits').doc(key);
  const now = Date.now();
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    let n = 0;
    let reset = now + windowMs;
    if (snap.exists && snap.get('reset') > now) {
      n = snap.get('n') || 0;
      reset = snap.get('reset');
    }
    if (overCap(n, reset, now, max)) {
      return Math.max(1, Math.ceil((reset - now) / 1000));
    }
    n += 1;
    tx.set(ref, { n, reset, expireAt: admin.firestore.Timestamp.fromMillis(reset) });
    return 0;
  });
}

function pipeFile(res, filePath, contentType) {
  const stream = bucket.file(filePath).createReadStream();
  stream.on('error', (err) => {
    console.error(err);
    if (!res.headersSent) send(res, 500, { error: 'try_again' });
    else res.destroy();
  });
  res.status(200);
  res.set('Content-Type', contentType);
  res.set('X-Content-Type-Options', 'nosniff');
  res.set('Cache-Control', 'private, max-age=3600');
  stream.pipe(res);
}

function numberList(value) {
  return Array.isArray(value) ? value.filter((item) => typeof item === 'string') : [];
}

function capReaches(reaches, blockedNumbers) {
  const blocked = new Set(blockedNumbers);
  const entries = Object.entries(reaches || {}).filter(
    ([, row]) => row && typeof row.number === 'string',
  );
  const pinned = entries.filter(([, row]) => blocked.has(row.number));
  const rest = entries.filter(([, row]) => !blocked.has(row.number));
  rest.sort((a, b) => (b[1].at || 0) - (a[1].at || 0));
  const room = Math.max(0, 30 - pinned.length);
  return Object.fromEntries([...pinned, ...rest.slice(0, room)]);
}

function publicView(row, distanceKm) {
  const point = publicPoint(row.lat, row.lng);
  const km = publicKm(distanceKm);
  return { ...row, lat: point.lat, lng: point.lng, km, band: band(km) };
}

function nameIn(names, lang) {
  if (names && names[lang]) return names[lang];
  if (names && names.en) return names.en;
  return '';
}

function resolvedKind(id, data) {
  const stored = data && data.kind;
  if (stored === 'parent' || stored === 'job') return stored;
  return 'parent';
}

let seeding = null;
async function seed() {
  if (seeding) return seeding;
  seeding = (async () => {
    const existing = await db.collection('categories').limit(1).get();
    if (!existing.empty) return;
    for (const row of SEED) {
      const png = await sharp({
        create: {
          width: 256,
          height: 256,
          channels: 3,
          background: row.color,
        },
      })
        .png()
        .toBuffer();
      const path = `covers/${row.id}.png`;
      const token = crypto.randomUUID();
      await bucket.file(path).save(png, {
        resumable: false,
        metadata: {
          contentType: 'image/png',
          cacheControl: 'public, max-age=31536000, immutable',
          metadata: { firebaseStorageDownloadTokens: token },
        },
      });
      await db.collection('categories').doc(row.id).set({
        parentId: row.parentId,
        sort: row.sort,
        active: true,
        kind: row.kind,
        names: NAMES[row.id],
        coverPath: path,
        coverUrl: publicUrl(bucket.name, path, token),
      });
    }
  })().catch((err) => {
    seeding = null;
    throw err;
  });
  return seeding;
}

async function readReadyFile(path) {
  const [buf] = await bucket.file(path).download();
  return buf;
}

async function thumbBytes(buf) {
  return sharp(buf, { failOn: 'error', limitInputPixels: 12_000_000 })
    .rotate()
    .resize({ width: THUMB_EDGE, height: THUMB_EDGE, fit: 'inside', withoutEnlargement: true })
    .webp({ quality: 70 })
    .toBuffer();
}

async function stampCover(doc) {
  if (doc.get('coverUrl')) return doc.get('coverUrl');
  const coverPath = doc.get('coverPath');
  if (!coverPath) return '';
  try {
    const file = bucket.file(coverPath);
    const [exists] = await file.exists();
    if (!exists) return '';
    const [meta] = await file.getMetadata();
    const stored = meta.metadata && meta.metadata.firebaseStorageDownloadTokens;
    let token = stored ? String(stored).split(',')[0] : '';
    if (!token) {
      token = crypto.randomUUID();
      await file.setMetadata({
        cacheControl: meta.cacheControl || 'public, max-age=31536000, immutable',
        metadata: { ...(meta.metadata || {}), firebaseStorageDownloadTokens: token },
      });
    }
    const url = publicUrl(bucket.name, coverPath, token);
    await doc.ref.update({ coverUrl: url });
    return url;
  } catch (err) {
    console.error(err);
    return '';
  }
}

async function acceptUpload(kind, buf) {
  const sniffed = sniff(buf);
  if (!sniffed || !KIND_TYPE[kind] || !KIND_TYPE[kind].has(sniffed)) return { error: 'type' };
  if (kind === 'image') {
    try {
      const img = sharp(buf, { failOn: 'error', limitInputPixels: 12_000_000 });
      const meta = await img.metadata();
      const width = meta.width || 0;
      const height = meta.height || 0;
      const pixels = width * height;
      if (!pixels || pixels > 12_000_000) return { error: 'pixels' };
      const thumb = needsThumb(width, height) ? await thumbBytes(buf) : null;
      if (sniffed === 'webp') return { buf, contentType: 'image/webp', thumb };
      const out = await img
        .rotate()
        .resize({ width: 1600, height: 1600, fit: 'inside', withoutEnlargement: true })
        .jpeg({ quality: 80 })
        .toBuffer();
      return { buf: out, contentType: 'image/jpeg', rewrite: true, thumb };
    } catch (_) {
      return { error: 'type' };
    }
  }
  const info = sniffed === 'mp4' ? parseMp4(buf) : sniffed === 'wav' ? parseWav(buf) : parseMp3(buf);
  const problem = limitsFor(kind, info);
  if (problem) return { error: problem };
  let contentType = 'audio/mpeg';
  if (kind === 'video') contentType = 'video/mp4';
  else if (sniffed === 'wav') contentType = 'audio/wav';
  else if (sniffed === 'mp4') contentType = 'audio/mp4';
  return { buf, contentType };
}

function card(req, doc, distanceKm) {
  const data = doc.data();
  const country = isoCountry(data.lat, data.lng);
  return {
    id: doc.id,
    posterUrl: data.posterUrl || (data.posterPath ? fileUrl(req, `poster:${doc.id}`) : ''),
    thumbUrl: data.thumbUrl || '',
    daysAgo: daysAgo(data.createdAt || Date.now()),
    createdAt: data.createdAt || Date.now(),
    km: Math.round(distanceKm),
    band: band(distanceKm),
    langs: data.langs || [],
    hasVideo: !!data.hasVideo,
    lat: data.lat,
    lng: data.lng,
    categoryId: data.categoryId,
    status: data.status,
    ...(country ? { country } : {}),
  };
}

async function deleteStep(uid, cursor) {
  if (!cursor || cursor === 'posts') {
    const snap = await db.collection('posts').where('uid', '==', uid).limit(15).get();
    for (const doc of snap.docs) {
      const before = await parentFor(doc.data());
      const written = await db.runTransaction(async (tx) => {
        const ids = await syncShelves(tx, shelfOps(before, null, doc.id));
        tx.delete(doc.ref);
        return ids;
      });
      dropShelfCache(written);
    }
    return { cursor: snap.size === 15 ? 'posts' : 'media' };
  }
  if (cursor === 'media') {
    const snap = await db.collection('media').where('uid', '==', uid).limit(8).get();
    for (const doc of snap.docs) {
      if (doc.get('path')) await bucket.file(doc.get('path')).delete({ ignoreNotFound: true });
      if (doc.get('thumbPath')) await bucket.file(doc.get('thumbPath')).delete({ ignoreNotFound: true });
      await doc.ref.delete();
    }
    return { cursor: snap.size === 8 ? 'media' : 'chats' };
  }
  if (cursor === 'chats' || cursor.startsWith('chat:')) {
    let chatId = cursor.startsWith('chat:') ? cursor.slice(5) : '';
    if (!chatId) {
      const found = await db.collection('chats').where('members', 'array-contains', uid).limit(1).get();
      if (found.empty) return { cursor: 'user' };
      chatId = found.docs[0].id;
    }
    const ref = db.collection('chats').doc(chatId);
    const chat = await ref.get();
    if (!chat.exists || !(chat.get('members') || []).includes(uid)) return { cursor: 'chats' };
    const msgs = await ref.collection('msgs').limit(40).get();
    for (const doc of msgs.docs) await doc.ref.delete();
    if (msgs.size === 40) return { cursor: `chat:${chatId}` };
    await ref.delete();
    return { cursor: 'chats' };
  }
  const [posts, media, chats] = await Promise.all([
    db.collection('posts').where('uid', '==', uid).limit(1).get(),
    db.collection('media').where('uid', '==', uid).limit(1).get(),
    db.collection('chats').where('members', 'array-contains', uid).limit(1).get(),
  ]);
  if (!posts.empty) return { cursor: 'posts' };
  if (!media.empty) return { cursor: 'media' };
  if (!chats.empty) return { cursor: 'chats' };
  await db.collection('users').doc(uid).delete();
  try {
    await admin.auth().deleteUser(uid);
  } catch (err) {
    if (err.code !== 'auth/user-not-found') throw err;
  }
  return { done: true };
}

function afterCursor(query, cursor) {
  const raw = typeof cursor === 'string' ? cursor : '';
  const cut = raw.indexOf('|');
  if (cut < 1) return query.limit(20);
  const ms = Number(raw.slice(0, cut));
  const id = raw.slice(cut + 1);
  if (!Number.isFinite(ms) || !id) return query.limit(20);
  return query.startAfter(ms, id).limit(20);
}

function nextCursor(docs) {
  if (docs.length < 20) return null;
  const last = docs[docs.length - 1];
  const at = last.get('createdAt');
  if (typeof at !== 'number') return null;
  return `${at}|${last.id}`;
}

async function categoryCatalog(force = false) {
  if (!force && catalog && Date.now() - catalogAt < CATALOG_MS) return catalog;
  const snap = await db.collection('categories').get();
  const rows = [];
  for (const doc of snap.docs) {
    let coverUrl = doc.get('coverUrl') || '';
    if (!coverUrl && doc.get('coverPath')) coverUrl = await stampCover(doc);
    rows.push({ id: doc.id, ...doc.data(), ...(coverUrl ? { coverUrl } : {}) });
  }
  catalog = rows;
  catalogAt = Date.now();
  return catalog;
}

async function readShelf(id, bypass) {
  if (!bypass) {
    const hit = shelfMem.get(id);
    if (hit && Date.now() - hit.at < SHELF_MS) return hit.data;
  }
  const snap = await db.collection('feeds').doc(id).get();
  const data = snap.exists ? snap.data() : null;
  shelfMem.set(id, { at: Date.now(), data });
  return data;
}

function finerTouching(cell, lat, lng) {
  const box = hashBounds(cell);
  const midLat = (box.south + box.north) / 2;
  const midLng = (box.west + box.east) / 2;
  if (lat >= box.south && lat <= box.north && lng >= box.west && lng <= box.east) {
    return geohash(lat, lng, cell.length + 1);
  }
  const eps = 1e-5;
  let cLat = Math.min(box.north, Math.max(box.south, lat));
  let cLng = Math.min(box.east, Math.max(box.west, lng));
  if (cLat !== lat) cLat += Math.sign(midLat - cLat) * eps;
  if (cLng !== lng) cLng += Math.sign(midLng - cLng) * eps;
  const hash = geohash(cLat, cLng, cell.length + 1);
  return hash.startsWith(cell) ? hash : geohash(midLat, midLng, cell.length + 1);
}

async function childCards(parentId, hash, lat, lng, bypass) {
  const data = await readShelf(shelfId(parentId, hash), bypass);
  if (!data) return [];
  if (data.sharded !== true) return Array.isArray(data.cards) ? data.cards : [];
  return childCards(parentId, finerTouching(hash, lat, lng), lat, lng, bypass);
}

async function cardsFrom(parentId, hash, lat, lng, bypass) {
  const parentCell = hash.slice(0, 4);
  const data = await readShelf(shelfId(parentId, parentCell), bypass);
  if (!data) return [];
  if (data.sharded !== true) return Array.isArray(data.cards) ? data.cards : [];
  const finer = hash.length > 4 ? hash : finerTouching(parentCell, lat, lng);
  return childCards(parentId, finer, lat, lng, bypass);
}

async function feedPool(parentId, lat, lng, jobIds, bypass) {
  const cell = geohash(lat, lng, 4);
  const center = await readShelf(shelfId(parentId, cell), bypass);
  const origin = center && center.sharded === true ? geohash(lat, lng, 5) : cell;
  const centerCards = await cardsFrom(parentId, origin, lat, lng, bypass);
  const cards = [];
  const seen = new Set();
  function add(list) {
    for (const card of list) {
      if (!card || typeof card.id !== 'string' || seen.has(card.id)) continue;
      seen.add(card.id);
      cards.push(card);
    }
  }
  add(centerCards);
  const boxes = [];
  for (const neighbor of ring(origin)) {
    const include = wantNeighbor(centerCards, jobIds, lat, lng, neighbor);
    const box = hashBounds(neighbor);
    boxes.push({
      id: shelfId(parentId, neighbor),
      south: box.south,
      north: box.north,
      west: box.west,
      east: box.east,
      in: include,
    });
    if (include) add(await cardsFrom(parentId, neighbor, lat, lng, bypass));
  }
  return { cards, ring: boxes };
}

function poolPost(item, distanceKm) {
  const country = isoCountry(item.lat, item.lng);
  return publicView({
    id: item.id,
    posterUrl: item.posterUrl || '',
    thumbUrl: item.thumbUrl || '',
    daysAgo: daysAgo(item.createdAt || Date.now()),
    createdAt: item.createdAt || Date.now(),
    km: Math.round(distanceKm),
    band: band(distanceKm),
    langs: item.langs || [],
    hasVideo: !!item.hasVideo,
    lat: item.lat,
    lng: item.lng,
    categoryId: item.categoryId,
    status: 'active',
    ...(country ? { country } : {}),
  }, distanceKm);
}

function parentFromShelf(id) {
  const raw = id.slice(0, id.lastIndexOf('__'));
  return raw === 'root' ? '' : raw;
}

function writePacked(tx, ref, cards, cell) {
  const written = [ref.id];
  const placed = packShelf(cards, cell);
  if (!placed.sharded) {
    tx.set(ref, { cards: placed.cards });
    return written;
  }
  tx.set(ref, { sharded: true });
  const parentId = parentFromShelf(ref.id);
  for (const [finer, list] of placed.groups) {
    const child = db.collection('feeds').doc(shelfId(parentId, finer));
    const nested = packShelf(list, finer);
    if (!nested.sharded) {
      tx.set(child, { cards: nested.cards });
      written.push(child.id);
      continue;
    }
    tx.set(child, { sharded: true });
    written.push(child.id);
    for (const [deep, deepList] of nested.groups) {
      const grand = db.collection('feeds').doc(shelfId(parentId, deep));
      tx.set(grand, { cards: deepList });
      written.push(grand.id);
    }
  }
  return written;
}

async function readWritable(tx, parentId, cell, lat, lng) {
  const parentRef = db.collection('feeds').doc(shelfId(parentId, cell));
  const parent = await tx.get(parentRef);
  if (parent.exists && parent.get('sharded') === true) {
    const finer = geohash(lat, lng, cell.length + 1);
    const ref = db.collection('feeds').doc(shelfId(parentId, finer));
    return { ref, snap: await tx.get(ref), cell: finer };
  }
  return { ref: parentRef, snap: parent, cell };
}

async function syncShelves(tx, ops) {
  const rows = [];
  for (const op of ops) {
    if (!op.cell) continue;
    rows.push({ op, ...(await readWritable(tx, op.parentId || '', op.cell, op.lat, op.lng)) });
  }
  const groups = new Map();
  for (const row of rows) {
    const hit = groups.get(row.ref.path);
    if (hit) hit.ops.push(row.op);
    else groups.set(row.ref.path, { ...row, ops: [row.op] });
  }
  const written = [];
  for (const group of groups.values()) {
    let cards = group.snap.exists && Array.isArray(group.snap.get('cards'))
      ? group.snap.get('cards').slice()
      : [];
    for (const op of group.ops) {
      cards = cards.filter((card) => card && card.id !== op.postId);
      if (op.card) cards.push(op.card);
    }
    written.push(...writePacked(tx, group.ref, cards, group.cell));
  }
  return written;
}

function shelfOps(before, after, postId) {
  const ops = [];
  if (before && before.status === 'active' && before.cell) {
    ops.push({
      parentId: before.parentId || '',
      cell: before.cell,
      lat: before.lat,
      lng: before.lng,
      postId,
      card: null,
    });
  }
  if (after && after.status === 'active' && after.cell) {
    ops.push({
      parentId: after.parentId || '',
      cell: after.cell,
      lat: after.lat,
      lng: after.lng,
      postId,
      card: shelfCard(postId, after),
    });
  }
  return ops;
}

async function parentFor(data) {
  if (!data) return null;
  if (typeof data.parentId === 'string') return data;
  const rows = await categoryCatalog();
  const cat = rows.find((row) => row.id === data.categoryId);
  return { ...data, parentId: cat ? String(cat.parentId || '') : '' };
}

async function handle(req, res) {
  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }
  const path = pathOf(req);
  const bits = path.split('/').filter(Boolean);

  if (req.method === 'GET' && path === '/v1/health') {
    send(res, 200, { ok: true });
    return;
  }

  if (req.method === 'GET' && bits[0] === 'v1' && bits[1] === 'files' && bits[2]) {
    const id = decodeURIComponent(bits[2]);
    const ip = clientIp(req.get('x-forwarded-for'), req.ip);
    if (!tokenOk(id, req.query.t)) {
      const wait = pace(`bad_${ip}`, 30, 10_000);
      if (wait) {
        tooFast(res, wait);
        return;
      }
      send(res, 403, { error: 'try_again' });
      return;
    }
    const shared = id.startsWith('poster:') || id.startsWith('cover:');
    const wait = shared ? pace(`pub_${id}`, 80, 10_000) : pace(`file_${ip}_${id}`, 6, 30_000);
    if (wait) {
      tooFast(res, wait);
      return;
    }
    let filePath = null;
    let contentType = 'application/octet-stream';
    if (id.startsWith('poster:')) {
      const post = await db.collection('posts').doc(id.slice(7)).get();
      if (!post.exists || !post.get('posterPath')) {
        send(res, 404, { error: 'try_again' });
        return;
      }
      filePath = post.get('posterPath');
      contentType = 'image/jpeg';
    } else if (id.startsWith('cover:')) {
      const cat = await db.collection('categories').doc(id.slice(6)).get();
      if (!cat.exists || !cat.get('coverPath')) {
        send(res, 404, { error: 'try_again' });
        return;
      }
      filePath = cat.get('coverPath');
      contentType = 'image/png';
    } else {
      const media = await db.collection('media').doc(id).get();
      if (!media.exists || media.get('status') !== 'ready') {
        send(res, 404, { error: 'try_again' });
        return;
      }
      filePath = media.get('path');
      contentType = SERVE_TYPE[media.get('kind')] || media.get('contentType') || contentType;
      if (media.get('kind') === 'audio' && media.get('contentType') === 'audio/wav') {
        contentType = 'audio/wav';
      }
    }
    pipeFile(res, filePath, contentType);
    return;
  }

  const user = await authed(req, res);
  if (!user) return;
  const uid = user.uid;

  try {
    await seed();
  } catch (err) {
    console.error(err);
    send(res, 500, { error: 'try_again' });
    return;
  }

  if (req.method === 'GET' && path === '/v1/me') {
    const wait = pace(`me_${uid}`, 6, 10_000);
    if (wait) {
      tooFast(res, wait);
      return;
    }
    const snap = await db.collection('users').doc(uid).get();
    send(res, 200, {
      lang: snap.exists ? snap.get('lang') || null : null,
      whatsapp: snap.exists ? snap.get('whatsapp') || null : null,
      admin: user.admin === true,
      email: user.email || '',
    });
    return;
  }

  if (req.method === 'PUT' && path === '/v1/me') {
    const lang = LANGS.includes(req.body?.lang) ? req.body.lang : null;
    const whatsapp = typeof req.body?.whatsapp === 'string' ? req.body.whatsapp.trim() : '';
    if (whatsapp && !/^\+[1-9]\d{7,14}$/.test(whatsapp)) {
      send(res, 400, { error: 'try_again' });
      return;
    }
    const coords = pairCoord(req.body);
    if (!coords.ok) {
      send(res, 400, { error: 'try_again' });
      return;
    }
    const wait = pace(`mew_${uid}`, 8, 10_000);
    if (wait) {
      tooFast(res, wait);
      return;
    }
    const prev = await db.collection('users').doc(uid).get();
    const next = {
      lang: lang || (prev.exists ? prev.get('lang') : null),
      whatsapp: whatsapp || (prev.exists ? prev.get('whatsapp') : null),
      email: user.email || '',
      updatedAt: Date.now(),
    };
    if (coords.lat != null) {
      next.lat = coords.lat;
      next.lng = coords.lng;
    }
    await db.collection('users').doc(uid).set(next, { merge: true });
    send(res, 200, { lang: next.lang, whatsapp: next.whatsapp, admin: user.admin === true });
    return;
  }

  if (req.method === 'DELETE' && path === '/v1/me') {
    const wait = pace(`delme_${uid}`, 10, 1000);
    if (wait) {
      tooFast(res, wait);
      return;
    }
    const cursor = typeof req.query.cursor === 'string' ? req.query.cursor : '';
    const step = await deleteStep(uid, cursor);
    send(res, 200, step.done ? { ok: true } : { cursor: step.cursor });
    return;
  }

  if (req.method === 'GET' && path === '/v1/me/media') {
    const wait = pace(`mlib_${uid}`, 6, 10_000);
    if (wait) {
      tooFast(res, wait);
      return;
    }
    let mediaQuery = db.collection('media')
      .where('uid', '==', uid)
      .where('status', '==', 'ready')
      .where('kind', 'in', ['image', 'video', 'audio'])
      .orderBy('createdAt', 'desc')
      .orderBy(admin.firestore.FieldPath.documentId(), 'desc');
    mediaQuery = afterCursor(mediaQuery, req.query.cursor);
    const media = await mediaQuery.get();
    const rows = media.docs.map((d) => ({
      id: d.id,
      kind: d.get('kind'),
      url: d.get('url') || fileUrl(req, d.id),
    }));
    send(res, 200, { media: rows, cursor: nextCursor(media.docs) });
    return;
  }

  if (req.method === 'GET' && path === '/v1/me/posts') {
    const wait = pace(`mine_${uid}`, 6, 10_000);
    if (wait) {
      tooFast(res, wait);
      return;
    }
    let postQuery = db.collection('posts')
      .where('uid', '==', uid)
      .orderBy('createdAt', 'desc')
      .orderBy(admin.firestore.FieldPath.documentId(), 'desc');
    postQuery = afterCursor(postQuery, req.query.cursor);
    const posts = await postQuery.get();
    const me = await db.collection('users').doc(uid).get();
    const blocked = new Set(numberList(me.get('blockedNumbers')));
    const cats = await categoryCatalog();
    const byId = new Map(cats.map((row) => [row.id, row]));
    const lang = me.get('lang') || 'en';
    send(res, 200, {
      posts: posts.docs.map((doc) => {
        const data = doc.data();
        const reaches = Object.values(data.reaches || {})
          .filter((row) => row && typeof row.number === 'string')
          .map((row) => ({
            number: row.number,
            at: row.at || 0,
            blocked: blocked.has(row.number),
          }))
          .sort((a, b) => b.at - a.at);
        return {
          ...card(req, doc, 0),
          mine: true,
          status: data.status,
          langs: data.langs || [],
          categoryId: data.categoryId,
          categoryPath: categoryTrail(byId, data.categoryId, lang),
          mediaIds: data.mediaIds || [],
          contactsOpen: data.contactsOpen !== false,
          reaches,
        };
      }),
      cursor: nextCursor(posts.docs),
    });
    return;
  }

  if (req.method === 'POST' && path === '/v1/me/blocks') {
    const number = typeof req.body?.number === 'string' ? req.body.number.trim() : '';
    if (!/^\+[1-9]\d{7,14}$/.test(number)) {
      send(res, 400, { error: 'try_again' });
      return;
    }
    const wait = pace(`blocks_${uid}`, 8, 10_000);
    if (wait) {
      tooFast(res, wait);
      return;
    }
    const postId = typeof req.body?.postId === 'string' ? req.body.postId : '';
    const post = postId ? await db.collection('posts').doc(postId).get() : null;
    const known = post && post.exists && post.get('uid') === uid &&
      Object.values(post.get('reaches') || {}).some((row) => row && row.number === number);
    if (!known) {
      send(res, 404, { error: 'try_again' });
      return;
    }
    const blocked = req.body?.blocked === true;
    const userRef = db.collection('users').doc(uid);
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(userRef);
      const list = new Set(numberList(snap.get('blockedNumbers')));
      if (blocked) list.add(number);
      else list.delete(number);
      tx.set(userRef, { blockedNumbers: capBlocks(list) }, { merge: true });
    });
    send(res, 200, { blocked });
    return;
  }

  if (req.method === 'GET' && path === '/v1/feed') {
    const wait = pace(`feed_${uid}`, 8, 5_000);
    if (wait) {
      tooFast(res, wait);
      return;
    }
    const lang = LANGS.includes(req.query.lang) ? req.query.lang : 'en';
    const lat = coarse(req.query.lat);
    const lng = coarse(req.query.lng);
    const parentId = String(req.query.parentId || '');
    if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
      send(res, 400, { error: 'try_again' });
      return;
    }
    const all = await categoryCatalog();
    const children = all
      .filter((row) => (row.parentId || '') === parentId && row.active !== false)
      .sort((a, b) => (a.sort || 0) - (b.sort || 0));
    const headersOnly = req.query.cards === '0';
    const jobIds = headersOnly
      ? []
      : children.filter((row) => resolvedKind(row.id, row) === 'job').map((row) => row.id);
    const pool = headersOnly
      ? { cards: [], ring: [] }
      : await feedPool(parentId, lat, lng, jobIds, req.query.fresh === '1');
    const grouped = new Map();
    for (const item of pool.cards) {
      const list = grouped.get(item.categoryId) || [];
      list.push(item);
      grouped.set(item.categoryId, list);
    }
    const categories = children.map((row) => {
      const kind = resolvedKind(row.id, row);
      const list = kind === 'job' ? grouped.get(row.id) || [] : [];
      return {
        id: row.id,
        name: nameIn(row.names, lang),
        coverUrl: row.coverUrl || (row.coverPath ? fileUrl(req, `cover:${row.id}`) : ''),
        kind,
        posts: list.map((item) => poolPost(item, kmBetween(lat, lng, item.lat, item.lng))),
      };
    });
    const body = { categories, ring: pool.ring };
    const etag = `"${crypto.createHash('sha1').update(JSON.stringify(body)).digest('hex')}"`;
    res.set('ETag', etag);
    res.set('Cache-Control', 'private, max-age=3600');
    if (req.get('if-none-match') === etag) {
      res.status(304).end();
      return;
    }
    send(res, 200, body);
    return;
  }

  if (req.method === 'GET' && bits[0] === 'v1' && bits[1] === 'posts' && bits[2] && !bits[3]) {
    const wait = pace(`detail_${uid}`, 8, 5_000);
    if (wait) {
      tooFast(res, wait);
      return;
    }
    const doc = await db.collection('posts').doc(bits[2]).get();
    if (!doc.exists) {
      send(res, 404, { error: 'try_again' });
      return;
    }
    const data = doc.data();
    const mine = data.uid === uid;
    if (!mine && data.status !== 'active') {
      send(res, 404, { error: 'try_again' });
      return;
    }
    const point = mine ? { lat: data.lat, lng: data.lng } : publicPoint(data.lat, data.lng);
    const media = [];
    for (const id of data.mediaIds || []) {
      const m = await db.collection('media').doc(id).get();
      if (!m.exists || m.get('status') !== 'ready') continue;
      media.push({ id, kind: m.get('kind'), url: m.get('url') || fileUrl(req, id) });
    }
    send(res, 200, {
      id: doc.id,
      categoryId: data.categoryId,
      daysAgo: daysAgo(data.createdAt),
      band: 'near',
      langs: data.langs || [],
      status: data.status,
      lat: point.lat,
      lng: point.lng,
      mine,
      media,
      mediaIds: mine ? data.mediaIds || [] : undefined,
    });
    return;
  }

  if (req.method === 'POST' && bits[0] === 'v1' && bits[1] === 'posts' && bits[2] && bits[3] === 'reveal') {
    const channel = req.body?.channel;
    if (channel !== 'whatsapp' && channel !== 'phone') {
      send(res, 400, { error: 'try_again' });
      return;
    }
    const burstWait = pace(`revb_${uid}`, 3, 10_000);
    if (burstWait) {
      tooFast(res, burstWait);
      return;
    }
    const early = await alreadyOver(`rev_u_${uid}`, 25);
    if (early) {
      tooFast(res, early);
      return;
    }
    const postRef = db.collection('posts').doc(bits[2]);
    const doc = await postRef.get();
    if (!doc.exists || doc.get('status') !== 'active' || doc.get('uid') === uid) {
      send(res, 404, { error: 'try_again' });
      return;
    }
    if (doc.get('contactsOpen') === false) {
      send(res, 404, { error: 'try_again' });
      return;
    }
    const ownerRef = db.collection('users').doc(doc.get('uid'));
    const [seeker, owner] = await Promise.all([
      db.collection('users').doc(uid).get(),
      ownerRef.get(),
    ]);
    const seekerNumber = seeker.exists ? String(seeker.get('whatsapp') || '') : '';
    const ownerNumber = owner.exists ? String(owner.get('whatsapp') || '') : '';
    if (!/^\+[1-9]\d{7,14}$/.test(seekerNumber) || !/^\+[1-9]\d{7,14}$/.test(ownerNumber)) {
      send(res, 404, { error: 'try_again' });
      return;
    }
    if (numberList(owner.get('blockedNumbers')).includes(seekerNumber)) {
      send(res, 404, { error: 'try_again' });
      return;
    }
    const capped = await limited(`rev_u_${uid}`, 25, 86400_000);
    if (capped) {
      tooFast(res, capped);
      return;
    }
    await db.runTransaction(async (tx) => {
      const post = await tx.get(postRef);
      const ownerSnap = await tx.get(ownerRef);
      if (!post.exists) return;
      const reaches = { ...(post.get('reaches') || {}) };
      reaches[uid] = { number: seekerNumber, at: Date.now() };
      tx.update(postRef, {
        reaches: capReaches(reaches, numberList(ownerSnap.get('blockedNumbers'))),
      });
    });
    const digits = ownerNumber.replace(/\D/g, '');
    const url = channel === 'whatsapp' ? `https://wa.me/${digits}` : `tel:${ownerNumber}`;
    send(res, 200, { url });
    return;
  }

  if (req.method === 'POST' && bits[0] === 'v1' && bits[1] === 'posts' && bits[2] && bits[3] === 'pause') {
    const wait = pace(`pause_${uid}`, 8, 10_000);
    if (wait) {
      tooFast(res, wait);
      return;
    }
    const doc = await db.collection('posts').doc(bits[2]).get();
    if (!doc.exists || doc.get('uid') !== uid) {
      send(res, 404, { error: 'try_again' });
      return;
    }
    const paused = req.body?.paused !== false;
    const before = await parentFor(doc.data());
    const next = { ...before, status: paused ? 'paused' : 'active' };
    const written = await db.runTransaction(async (tx) => {
      const snap = await tx.get(doc.ref);
      if (!snap.exists || snap.get('uid') !== uid) return [];
      const ids = await syncShelves(tx, shelfOps(before, next, doc.id));
      tx.update(doc.ref, { status: next.status });
      return ids;
    });
    dropShelfCache(written);
    send(res, 200, { status: next.status });
    return;
  }

  if (req.method === 'POST' && bits[0] === 'v1' && bits[1] === 'posts' && bits[2] && bits[3] === 'block') {
    const wait = pace(`pblock_${uid}`, 8, 10_000);
    if (wait) {
      tooFast(res, wait);
      return;
    }
    const doc = await db.collection('posts').doc(bits[2]).get();
    if (!doc.exists || doc.get('uid') !== uid) {
      send(res, 404, { error: 'try_again' });
      return;
    }
    const blocked = req.body?.blocked === true;
    await doc.ref.update({ contactsOpen: !blocked });
    send(res, 200, { contactsOpen: !blocked });
    return;
  }

  if (req.method === 'POST' && path === '/v1/media/upload-url') {
    const burstWait = pace(`up_${uid}`, 12, 10_000);
    if (burstWait) {
      tooFast(res, burstWait);
      return;
    }
    const capped = await limited(`up_${uid}`, 40, 86400_000);
    if (capped) {
      tooFast(res, capped);
      return;
    }
    const kind = req.body?.kind;
    const bytes = Number(req.body?.bytes || 0);
    const contentType = String(req.body?.contentType || '');
    const ext = extFor(kind, contentType);
    if (!MAX_BYTES[kind] || bytes < 32 || bytes > MAX_BYTES[kind] || !ext) {
      send(res, 400, { error: 'try_again' });
      return;
    }
    const id = crypto.randomBytes(12).toString('hex');
    const objectPath = `users/${uid}/${id}.${ext}`;
    await db.collection('media').doc(id).set({
      uid,
      kind,
      status: 'pending',
      bytes,
      path: objectPath,
      contentType,
      createdAt: Date.now(),
      expireAt: admin.firestore.Timestamp.fromMillis(Date.now() + 86_400_000),
    });
    let uploadUrl = '';
    try {
      const origin = req.get('origin') || '';
      const webOrigin = origin === 'https://worky-93fbc.web.app' ||
        origin === 'https://worky-93fbc.firebaseapp.com' ||
        origin === 'https://www.kaambazaar.org' ||
        origin === 'https://kaambazaar.org';
      const [uri] = await bucket.file(objectPath).createResumableUpload({
        metadata: {
          contentType,
          customTime: new Date(Date.now() + 86_400_000).toISOString(),
        },
        ...(webOrigin ? { origin } : {}),
      });
      uploadUrl = uri;
    } catch (err) {
      await db.collection('media').doc(id).delete();
      throw err;
    }
    send(res, 200, {
      mediaId: id,
      uploadUrl,
      finishUrl: `${apiRoot(req)}/v1/media/raw/${id}?t=${tokenFor(id, 86_400_000)}`,
    });
    return;
  }

  if (req.method === 'PUT' && bits[0] === 'v1' && bits[1] === 'media' && bits[2] === 'raw' && bits[3]) {
    const id = bits[3];
    if (!tokenOk(id, req.query.t)) {
      send(res, 403, { error: 'try_again' });
      return;
    }
    const wait = pace(`raw_${uid}`, 12, 10_000);
    if (wait) {
      tooFast(res, wait);
      return;
    }
    const doc = await db.collection('media').doc(id).get();
    if (!doc.exists || doc.get('uid') !== uid || doc.get('status') !== 'pending') {
      send(res, 404, { error: 'try_again' });
      return;
    }
    const objectPath = doc.get('path');
    const file = bucket.file(objectPath);
    const [exists] = await file.exists();
    if (!exists) {
      send(res, 400, { error: 'try_again' });
      return;
    }
    const [meta] = await file.getMetadata();
    const bytes = Number(meta.size || 0);
    if (bytes < 32 || bytes > MAX_BYTES[doc.get('kind')]) {
      await file.delete({ ignoreNotFound: true });
      await doc.ref.delete();
      send(res, 400, { error: 'try_again' });
      return;
    }
    let buf;
    if (doc.get('kind') === 'video') {
      buf = await clipMp4(bytes, async (start, end) => {
        const [part] = await file.download({ start, end });
        return part;
      });
      if (!buf) {
        await file.delete({ ignoreNotFound: true });
        await doc.ref.delete();
        send(res, 400, { error: 'try_again' });
        return;
      }
    } else {
      const [full] = await file.download();
      buf = full;
    }
    const accepted = await acceptUpload(doc.get('kind'), buf);
    if (accepted.error) {
      await file.delete({ ignoreNotFound: true });
      await doc.ref.delete();
      send(res, 400, { error: 'try_again' });
      return;
    }
    const token = crypto.randomUUID();
    const cacheControl = 'public, max-age=31536000, immutable';
    const metadata = {
      contentType: accepted.contentType,
      cacheControl,
      metadata: { firebaseStorageDownloadTokens: token },
    };
    if (accepted.rewrite) {
      await file.save(accepted.buf, { resumable: false, metadata });
    } else {
      await file.setMetadata(metadata);
    }
    const url = publicUrl(bucket.name, objectPath, token);
    let thumbUrl = '';
    let thumbPath = '';
    if (accepted.thumb) {
      const dot = objectPath.lastIndexOf('.');
      thumbPath = `${dot === -1 ? objectPath : objectPath.slice(0, dot)}_thumb.webp`;
      const thumbToken = crypto.randomUUID();
      await bucket.file(thumbPath).save(accepted.thumb, {
        resumable: false,
        metadata: {
          contentType: 'image/webp',
          cacheControl,
          metadata: { firebaseStorageDownloadTokens: thumbToken },
        },
      });
      thumbUrl = publicUrl(bucket.name, thumbPath, thumbToken);
    }
    await file.setMetadata({ customTime: null });
    await doc.ref.update({
      status: 'ready',
      contentType: accepted.contentType,
      bytes: accepted.rewrite ? accepted.buf.length : bytes,
      url,
      expireAt: admin.firestore.FieldValue.delete(),
      ...(thumbUrl ? { thumbUrl, thumbPath } : {}),
    });
    send(res, 200, { mediaId: id, url });
    return;
  }

  if ((req.method === 'POST' || req.method === 'PATCH') && (path === '/v1/posts' || (bits[1] === 'posts' && bits[2] && !bits[3]))) {
    if (req.method === 'POST') {
      const burstWait = pace(`post_${uid}`, 3, 10_000);
      if (burstWait) {
        tooFast(res, burstWait);
        return;
      }
      const capped = await limited(`post_${uid}`, 20, 86400_000);
      if (capped) {
        tooFast(res, capped);
        return;
      }
    } else {
      const wait = pace(`edit_${uid}`, 8, 10_000);
      if (wait) {
        tooFast(res, wait);
        return;
      }
    }
    const saved = await savePost(req, uid, req.method === 'PATCH' ? bits[2] : null);
    send(res, saved.error ? saved.status : 200, saved.error ? { error: 'try_again' } : saved.body);
    return;
  }

  if (req.method === 'DELETE' && bits[0] === 'v1' && bits[1] === 'posts' && bits[2] && !bits[3]) {
    const wait = pace(`delp_${uid}`, 8, 10_000);
    if (wait) {
      tooFast(res, wait);
      return;
    }
    const doc = await db.collection('posts').doc(bits[2]).get();
    if (!doc.exists || doc.get('uid') !== uid) {
      send(res, 404, { error: 'try_again' });
      return;
    }
    const before = await parentFor(doc.data());
    const written = await db.runTransaction(async (tx) => {
      const snap = await tx.get(doc.ref);
      if (!snap.exists) return [];
      const ids = await syncShelves(tx, shelfOps(before, null, doc.id));
      tx.delete(doc.ref);
      return ids;
    });
    dropShelfCache(written);
    send(res, 200, { ok: true });
    return;
  }

  if (bits[0] === 'v1' && bits[1] === 'admin') {
    if (user.admin !== true) {
      send(res, 403, { error: 'try_again' });
      return;
    }
    if (req.method === 'GET' && path === '/v1/admin/categories') {
      const cats = await db.collection('categories').get();
      const categories = [];
      for (const d of cats.docs) {
        let coverUrl = d.get('coverUrl') || '';
        if (!coverUrl && d.get('coverPath')) coverUrl = await stampCover(d);
        if (!coverUrl && d.get('coverPath')) coverUrl = fileUrl(req, `cover:${d.id}`);
        categories.push({
          id: d.id,
          ...d.data(),
          kind: resolvedKind(d.id, d.data()),
          coverUrl,
        });
      }
      send(res, 200, { categories });
      return;
    }
    if (req.method === 'POST' && path === '/v1/admin/categories') {
      const wait = pace(`admin_${uid}`, 20, 10_000);
      if (wait) {
        tooFast(res, wait);
        return;
      }
      const made = await writeCategory(req, null);
      send(res, made.error ? 400 : 200, made.error ? { error: made.error } : made.body);
      return;
    }
    if (req.method === 'PATCH' && bits[2] === 'categories' && bits[3] && !bits[4]) {
      const wait = pace(`admin_${uid}`, 20, 10_000);
      if (wait) {
        tooFast(res, wait);
        return;
      }
      const made = await writeCategory(req, bits[3]);
      send(res, made.error ? 400 : 200, made.error ? { error: made.error } : made.body);
      return;
    }
    if (req.method === 'POST' && bits[2] === 'categories' && bits[3] && bits[4] === 'hide') {
      const wait = pace(`admin_${uid}`, 20, 10_000);
      if (wait) {
        tooFast(res, wait);
        return;
      }
      await db.collection('categories').doc(bits[3]).update({ active: req.body?.active === true });
      send(res, 200, { ok: true });
      return;
    }
  }

  send(res, 404, { error: 'try_again' });
}

async function ownedMedia(uid, ids) {
  if (!Array.isArray(ids) || ids.length > 15) return null;
  const out = [];
  let images = 0;
  let videos = 0;
  let audios = 0;
  let posterPath = '';
  let posterUrl = '';
  let thumbUrl = '';
  let hasVideo = false;
  for (const id of ids) {
    if (typeof id !== 'string') return null;
    const doc = await db.collection('media').doc(id).get();
    if (!doc.exists || doc.get('uid') !== uid || doc.get('status') !== 'ready') return null;
    const kind = doc.get('kind');
    if (kind === 'voice') return null;
    if (kind === 'image') images += 1;
    if (kind === 'video') {
      videos += 1;
      hasVideo = true;
    }
    if (kind === 'audio') audios += 1;
    if (kind === 'image' && !posterPath) {
      posterPath = doc.get('path');
      posterUrl = doc.get('url') || '';
      thumbUrl = doc.get('thumbUrl') || '';
    }
    out.push(id);
  }
  if (images < 1 || images > 5 || videos > 5 || audios > 5) return null;
  return { ids: out, posterPath, posterUrl, thumbUrl, hasVideo };
}

async function savePost(req, uid, existingId) {
  const categoryId = String(req.body?.categoryId || '');
  const cat = await db.collection('categories').doc(categoryId).get();
  if (!cat.exists || cat.get('active') === false || resolvedKind(categoryId, cat.data()) !== 'job') {
    return { error: true, status: 400 };
  }
  const lat = coarse(req.body?.lat);
  const lng = coarse(req.body?.lng);
  if (!Number.isFinite(lat) || !Number.isFinite(lng) || Math.abs(lat) > 90 || Math.abs(lng) > 180) {
    return { error: true, status: 400 };
  }
  const langs = Array.isArray(req.body?.langs) ? req.body.langs.filter((l) => LANGS.includes(l)) : [];
  if (!langs.length) return { error: true, status: 400 };
  const media = await ownedMedia(uid, req.body?.mediaIds);
  if (!media) return { error: true, status: 400 };
  const payload = {
    uid,
    categoryId,
    lat,
    lng,
    cell: geohash(lat, lng, 4),
    langs,
    mediaIds: media.ids,
    posterPath: media.posterPath,
    posterUrl: media.posterUrl || '',
    thumbUrl: media.thumbUrl || '',
    hasVideo: media.hasVideo,
    parentId: String(cat.get('parentId') || ''),
    updatedAt: Date.now(),
  };
  const ref = existingId
    ? db.collection('posts').doc(existingId)
    : db.collection('posts').doc();
  const prevSnap = existingId ? await ref.get() : null;
  if (existingId && (!prevSnap.exists || prevSnap.get('uid') !== uid)) {
    return { error: true, status: 404 };
  }
  const before = prevSnap ? await parentFor(prevSnap.data()) : null;
  const written = await db.runTransaction(async (tx) => {
    if (existingId) {
      const snap = await tx.get(ref);
      if (!snap.exists || snap.get('uid') !== uid) {
        throw Object.assign(new Error('missing'), { status: 404 });
      }
    }
    const createdAt = before && before.createdAt ? before.createdAt : Date.now();
    const status = before && before.status ? before.status : 'active';
    const next = { ...payload, status, createdAt };
    const ops = shelfOps(before, next, ref.id);
    const ids = await syncShelves(tx, ops);
    if (existingId) tx.update(ref, next);
    else tx.set(ref, next);
    return ids;
  }).catch((err) => {
    if (err.status === 404) return null;
    throw err;
  });
  if (!written) return { error: true, status: 404 };
  dropShelfCache(written);
  return { body: { id: ref.id } };
}

async function writeCategory(req, id) {
  const names = req.body?.names || {};
  const clean = {};
  for (const lang of LANGS) {
    const value = String(names[lang] || '').trim();
    if (!value || value.length > 40) return { error: 'name' };
    clean[lang] = value;
  }
  const kind = req.body?.kind === 'job' || req.body?.kind === 'parent' ? req.body.kind : '';
  if (!kind) return { error: 'kind' };
  const parentId = String(req.body?.parentId || '');
  if (parentId) {
    const parent = await db.collection('categories').doc(parentId).get();
    if (!parent.exists || resolvedKind(parentId, parent.data()) !== 'parent') return { error: 'parent' };
  }
  const sort = Number(req.body?.sort || 0);
  const ref = id ? db.collection('categories').doc(id) : db.collection('categories').doc();
  let coverPath = null;
  let coverUrl = '';
  let previous = '';
  if (id) {
    const prev = await ref.get();
    if (!prev.exists) return { error: 'missing' };
    coverPath = prev.get('coverPath');
    coverUrl = prev.get('coverUrl') || '';
    previous = coverPath || '';
  }
  if (req.body?.coverMediaId) {
    const media = await db.collection('media').doc(String(req.body.coverMediaId)).get();
    if (!media.exists || media.get('kind') !== 'image' || media.get('status') !== 'ready') {
      return { error: 'cover' };
    }
    coverPath = media.get('path');
    coverUrl = media.get('url') || '';
  }
  if (!coverPath) return { error: 'cover' };
  if (!String(coverPath).startsWith('covers/')) {
    const owned = await ownCover(ref.id, coverPath);
    coverPath = owned.coverPath;
    coverUrl = owned.coverUrl;
  }
  if (previous.startsWith('covers/') && previous !== coverPath) {
    await bucket.file(previous).delete({ ignoreNotFound: true });
  }
  const data = { parentId, sort, names: clean, coverPath, coverUrl, active: true, kind };
  await ref.set(data, { merge: true });
  dropCatalog();
  return { body: { id: ref.id } };
}

async function ownCover(categoryId, srcPath) {
  const dot = srcPath.lastIndexOf('.');
  const ext = dot === -1 ? 'jpg' : srcPath.slice(dot + 1);
  const dest = `covers/${categoryId}.${ext}`;
  if (srcPath !== dest) await bucket.file(srcPath).copy(bucket.file(dest));
  const token = crypto.randomUUID();
  const contentType = ext === 'png' ? 'image/png' : ext === 'webp' ? 'image/webp' : 'image/jpeg';
  await bucket.file(dest).setMetadata({
    contentType,
    cacheControl: 'public, max-age=31536000, immutable',
    metadata: { firebaseStorageDownloadTokens: token },
  });
  return { coverPath: dest, coverUrl: publicUrl(bucket.name, dest, token) };
}

exports.api = onRequest(
  {
    cors: true,
    memory: '512MiB',
    timeoutSeconds: 60,
    maxInstances: 1,
    invoker: 'public',
    region: 'us-central1',
    secrets: [fileTokenKey],
  },
  async (req, res) => {
    try {
      await handle(req, res);
    } catch (err) {
      console.error(err);
      if (!res.headersSent) send(res, 500, { error: 'try_again' });
    }
  },
);

exports._test = { tokenFor, tokenOk, NAMES, SEED };
