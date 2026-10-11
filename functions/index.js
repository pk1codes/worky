const crypto = require('crypto');
const admin = require('firebase-admin');
const { onRequest } = require('firebase-functions/v2/https');
const { defineSecret } = require('firebase-functions/params');
const sharp = require('sharp');
const { LANGS, coarse, geohash, kmBetween, band, daysAgo, publicPoint, publicKm } = require('./lib/geo');
const { parseMp4, parseWav, parseMp3, sniff, KIND_TYPE, SERVE_TYPE, limitsFor, extFor, publicUrl, THUMB_EDGE, needsThumb } = require('./lib/media');
const { DAY_MS, VIDEO_MS, pairId, pairMembers, cleanText, googleMatch, meetBody, meetUrl, viewMessage } = require('./lib/talk');

admin.initializeApp({
  projectId: 'worky-93fbc',
  storageBucket: 'worky-93fbc.firebasestorage.app',
});

const db = admin.firestore();
const bucket = admin.storage().bucket();
const fileTokenKey = defineSecret('FILE_TOKEN_KEY');

function fileKey() {
  return process.env.FILE_TOKEN_KEY || 'worky-local-file-key';
}
const MAX_BYTES = { image: 8_000_000, video: 20_000_000, audio: 8_000_000, voice: 400_000 };

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
  'asst-driller': { en: 'Asst Driller' },
  driller: { en: 'Driller' },
  medic: { en: 'Medic' },
  'service-companies': { en: 'Service Companies Jobs' },
  'oil-company-jobs': { en: 'Oil Company Jobs' },
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
  { id: 'asst-driller', parentId: 'oil-field-rigs', sort: 0, color: '#9A3412', kind: 'job' },
  { id: 'driller', parentId: 'oil-field-rigs', sort: 1, color: '#7F1D1D', kind: 'job' },
  { id: 'medic', parentId: 'oil-field-rigs', sort: 2, color: '#155E75', kind: 'job' },
  { id: 'service-companies', parentId: 'oil-field-rigs', sort: 3, color: '#365314', kind: 'parent' },
  { id: 'oil-company-jobs', parentId: 'oil-field-rigs', sort: 4, color: '#1E3A8A', kind: 'parent' },
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
    n += 1;
    tx.set(ref, { n, reset });
    return n > max;
  });
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
  if (!sniffed || !KIND_TYPE[kind].has(sniffed)) return { error: 'type' };
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
  };
}

async function talkInbox(uid) {
  const snap = await db.collection('chats')
    .where('members', 'array-contains', uid)
    .orderBy('updatedAt', 'desc')
    .limit(30)
    .get();
  return snap.docs.filter((doc) => doc.get('last')).map((doc) => {
    const last = doc.get('last') || {};
    const unread = doc.get('unread') || {};
    return {
      id: doc.id,
      kind: last.kind || 'text',
      preview: last.text || '',
      at: last.at || doc.get('updatedAt') || 0,
      unread: unread[uid] || 0,
      closed: doc.get('closed') === true,
    };
  });
}

function otherOf(members, uid) {
  return members.find((id) => id !== uid) || '';
}

function talkPreview(kind, text) {
  if (kind === 'voice') return 'Voice';
  if (kind === 'video') return 'Video';
  return String(text || '').slice(0, 80);
}

async function loadTalk(id, uid) {
  const members = pairMembers(id, uid);
  if (!members) return null;
  const ref = db.collection('chats').doc(id);
  const snap = await ref.get();
  if (!snap.exists) return { ref, snap, members, missing: true };
  const stored = snap.get('members') || [];
  if (!stored.includes(uid)) return null;
  return { ref, snap, members: stored, missing: false };
}

async function talkRows(req, ref, now, closed = false) {
  const msgs = await ref.collection('msgs').orderBy('at', 'desc').limit(40).get();
  const rows = [];
  let batch = null;
  let drops = 0;
  for (const doc of msgs.docs) {
    const data = doc.data();
    const stale = data.kind === 'video' && data.meetUrl && (closed || !(data.expiresAt > now));
    if (stale) {
      batch = batch || db.batch();
      batch.update(doc.ref, { meetUrl: admin.firestore.FieldValue.delete() });
      drops += 1;
      delete data.meetUrl;
    }
    const voice = data.kind === 'voice' ? fileUrl(req, data.mediaId) : '';
    rows.push(viewMessage({ id: doc.id, ...data }, now, voice));
  }
  if (drops) await batch.commit();
  rows.reverse();
  return rows;
}

async function liveVideo(ref, now) {
  const msgs = await ref.collection('msgs').orderBy('at', 'desc').limit(40).get();
  for (const doc of msgs.docs) {
    const data = doc.data();
    if (data.kind === 'video' && data.meetUrl && data.expiresAt > now) {
      return { id: doc.id, ...data };
    }
  }
  return null;
}

async function markRead(ref, snap, uid) {
  const unread = { ...(snap.get('unread') || {}) };
  if (!unread[uid]) return;
  unread[uid] = 0;
  await ref.update({ unread });
}

async function ensurePair(uid, owner, postId) {
  const id = pairId(uid, owner);
  if (!id) return { status: 404 };
  const ref = db.collection('chats').doc(id);
  const snap = await ref.get();
  if (snap.exists) {
    if (snap.get('closed') === true) return { status: 404, id, ref, snap };
    return { id, ref, snap };
  }
  const post = await db.collection('posts').doc(postId).get();
  if (!post.exists || post.get('uid') !== owner || post.get('status') !== 'active') return { status: 404 };
  if (post.get('contactsOpen') === false) return { status: 404 };
  if (await limited(`pair_${uid}`, 3, DAY_MS)) return { status: 429 };
  try {
    await ref.create({
      members: [uid, owner].sort(),
      postId,
      updatedAt: Date.now(),
      unread: {},
      closed: false,
    });
  } catch (err) {
    if (err.code !== 6 && err.code !== 'already-exists') throw err;
  }
  return { id, ref, snap: await ref.get() };
}

async function appendTalk(ref, uid, members, msg, preview) {
  const id = crypto.randomBytes(8).toString('hex');
  const at = Date.now();
  const other = otherOf(members, uid);
  await db.runTransaction(async (tx) => {
    const chat = await tx.get(ref);
    if (!chat.exists || chat.get('closed') === true) throw Object.assign(new Error('closed'), { status: 404 });
    const unread = { ...(chat.get('unread') || {}) };
    if (other) unread[other] = (unread[other] || 0) + 1;
    tx.set(ref.collection('msgs').doc(id), { ...msg, from: uid, at });
    tx.update(ref, {
      updatedAt: at,
      last: { kind: msg.kind, text: preview, from: uid, at },
      unread,
    });
  });
  return { id, at, other };
}

async function pingTalk(other, body, id) {
  if (!other) return;
  const user = await db.collection('users').doc(other).get();
  const tokens = numberList(user.get('pushTokens')).slice(-3);
  if (!tokens.length) return;
  try {
    const result = await admin.messaging().sendEachForMulticast({
      tokens,
      notification: { title: 'Worky', body },
      data: { pairId: id },
      android: { priority: 'high' },
    });
    const left = tokens.filter((_, i) => result.responses[i].success);
    if (left.length !== tokens.length) {
      await db.collection('users').doc(other).set({ pushTokens: left }, { merge: true });
    }
  } catch (err) {
    console.error(err);
  }
}

async function messageFrom(req, uid) {
  const text = cleanText(req.body?.text);
  const mediaId = typeof req.body?.mediaId === 'string' ? req.body.mediaId : '';
  if (text && mediaId) return { status: 400 };
  if (text) {
    if (await limited(`txt_${uid}`, 400, DAY_MS)) return { status: 429 };
    return { msg: { kind: 'text', text }, preview: talkPreview('text', text) };
  }
  if (!mediaId) return { status: 400 };
  if (await limited(`voi_${uid}`, 60, DAY_MS)) return { status: 429 };
  const media = await db.collection('media').doc(mediaId).get();
  if (!media.exists || media.get('uid') !== uid || media.get('kind') !== 'voice' || media.get('status') !== 'ready') {
    return { status: 400 };
  }
  const durMs = Math.min(60_000, Math.max(0, Number(req.body?.durMs) || 0));
  return { msg: { kind: 'voice', mediaId, durMs }, preview: talkPreview('voice') };
}

const OWNED_CALENDAR = 'https://www.googleapis.com/auth/calendar.events.owned';

async function calendarJson(accessToken, method, path, body) {
  const response = await fetch(`https://www.googleapis.com/calendar/v3${path}`, {
    method,
    headers: {
      authorization: `Bearer ${accessToken}`,
      'content-type': 'application/json',
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  if (!response.ok) return null;
  const text = await response.text();
  if (!text) return {};
  return JSON.parse(text);
}

async function tokenInfo(accessToken) {
  const response = await fetch('https://oauth2.googleapis.com/tokeninfo', {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ access_token: accessToken }).toString(),
  });
  if (!response.ok) return null;
  return response.json();
}

async function createMeet(accessToken, uid) {
  const token = await tokenInfo(accessToken);
  if (!token) return null;
  const scopes = String(token.scope || '').split(/\s+/);
  if (!scopes.includes(OWNED_CALENDAR)) return null;
  const user = await admin.auth().getUser(uid);
  if (!googleMatch(token.sub, user.providerData)) return null;
  const created = await calendarJson(
    accessToken,
    'POST',
    '/calendars/primary/events?conferenceDataVersion=1',
    meetBody(Date.now(), crypto.randomBytes(8).toString('hex')),
  );
  if (!created || !created.id) return null;
  let url = meetUrl(created);
  let event = created;
  for (let i = 0; !url && i < 3; i += 1) {
    await new Promise((resolve) => setTimeout(resolve, 400));
    event = await calendarJson(
      accessToken,
      'GET',
      `/calendars/primary/events/${encodeURIComponent(created.id)}?conferenceDataVersion=1`,
    );
    url = meetUrl(event);
  }
  if (!url) return null;
  return { url, eventId: created.id };
}

async function deleteEvent(accessToken, eventId) {
  if (!eventId) return;
  await calendarJson(
    accessToken,
    'DELETE',
    `/calendars/primary/events/${encodeURIComponent(eventId)}`,
  );
}

async function talk(req, res, uid, path, bits) {
  if (req.method === 'PUT' && path === '/v1/me/push') {
    const token = typeof req.body?.token === 'string' ? req.body.token.trim() : '';
    if (token.length < 20 || token.length > 4096) {
      send(res, 400, { error: 'try_again' });
      return true;
    }
    const user = await db.collection('users').doc(uid).get();
    const tokens = numberList(user.get('pushTokens')).filter((item) => item !== token);
    tokens.push(token);
    await db.collection('users').doc(uid).set({ pushTokens: tokens.slice(-3) }, { merge: true });
    send(res, 200, { ok: true });
    return true;
  }

  const postTalk = bits[0] === 'v1' && bits[1] === 'posts' && bits[2] && bits[3] === 'talk';
  const pairTalk = bits[0] === 'v1' && bits[1] === 'talks' && bits[2];
  if (!postTalk && !pairTalk) return false;

  if (postTalk) {
    const post = await db.collection('posts').doc(bits[2]).get();
    if (!post.exists || post.get('uid') === uid) {
      send(res, 404, { error: 'try_again' });
      return true;
    }
    const owner = post.get('uid');
    const id = pairId(uid, owner);
    if (!id) {
      send(res, 404, { error: 'try_again' });
      return true;
    }
    if (req.method === 'GET' && !bits[4]) {
      const loaded = await loadTalk(id, uid);
      if (!loaded || loaded.missing) {
        send(res, 200, { pairId: '', closed: false, messages: [] });
        return true;
      }
      await markRead(loaded.ref, loaded.snap, uid);
      send(res, 200, {
        pairId: id,
        closed: loaded.snap.get('closed') === true,
        messages: await talkRows(req, loaded.ref, Date.now(), loaded.snap.get('closed') === true),
      });
      return true;
    }
    if (req.method === 'POST' && !bits[4]) {
      const made = await messageFrom(req, uid);
      if (made.status) {
        send(res, made.status, { error: 'try_again' });
        return true;
      }
      const room = await ensurePair(uid, owner, post.id);
      if (room.status) {
        send(res, room.status, { error: 'try_again' });
        return true;
      }
      try {
        const saved = await appendTalk(room.ref, uid, room.snap.get('members'), made.msg, made.preview);
        await pingTalk(saved.other, made.preview, room.id);
        send(res, 200, { pairId: room.id, message: { id: saved.id, at: saved.at, ...made.msg, from: uid } });
      } catch (err) {
        send(res, err.status || 500, { error: 'try_again' });
      }
      return true;
    }
    if (req.method === 'POST' && bits[4] === 'video') {
      await startVideo(req, res, uid, owner, post.id);
      return true;
    }
    send(res, 404, { error: 'try_again' });
    return true;
  }

  const loaded = await loadTalk(bits[2], uid);
  if (!loaded || loaded.missing) {
    send(res, 404, { error: 'try_again' });
    return true;
  }
  if (req.method === 'GET' && !bits[3]) {
    await markRead(loaded.ref, loaded.snap, uid);
    send(res, 200, {
      pairId: bits[2],
      closed: loaded.snap.get('closed') === true,
      messages: await talkRows(req, loaded.ref, Date.now(), loaded.snap.get('closed') === true),
    });
    return true;
  }
  if (req.method === 'POST' && bits[3] === 'block') {
    await loaded.ref.update({ closed: true });
    await talkRows(req, loaded.ref, Date.now(), true);
    send(res, 200, { closed: true });
    return true;
  }
  if (loaded.snap.get('closed') === true) {
    send(res, 404, { error: 'try_again' });
    return true;
  }
  if (req.method === 'POST' && !bits[3]) {
    const made = await messageFrom(req, uid);
    if (made.status) {
      send(res, made.status, { error: 'try_again' });
      return true;
    }
    try {
      const saved = await appendTalk(loaded.ref, uid, loaded.members, made.msg, made.preview);
      await pingTalk(saved.other, made.preview, bits[2]);
      send(res, 200, { pairId: bits[2], message: { id: saved.id, at: saved.at, ...made.msg, from: uid } });
    } catch (err) {
      send(res, err.status || 500, { error: 'try_again' });
    }
    return true;
  }
  if (req.method === 'POST' && bits[3] === 'video') {
    const owner = otherOf(loaded.members, uid);
    await startVideo(req, res, uid, owner, loaded.snap.get('postId') || '', bits[2]);
    return true;
  }
  send(res, 404, { error: 'try_again' });
  return true;
}

async function startVideo(req, res, uid, owner, postId, existingId) {
  const accessToken = typeof req.body?.accessToken === 'string' ? req.body.accessToken : '';
  if (accessToken.length < 20 || accessToken.length > 4096) {
    send(res, 400, { error: 'try_again' });
    return;
  }
  let room;
  if (existingId) {
    const loaded = await loadTalk(existingId, uid);
    if (!loaded || loaded.missing || loaded.snap.get('closed') === true) {
      send(res, 404, { error: 'try_again' });
      return;
    }
    room = { id: existingId, ref: loaded.ref, snap: loaded.snap };
  } else {
    room = await ensurePair(uid, owner, postId);
    if (room.status) {
      send(res, room.status, { error: 'try_again' });
      return;
    }
  }
  const now = Date.now();
  const live = await liveVideo(room.ref, now);
  if (live) {
    send(res, 200, {
      pairId: room.id,
      message: viewMessage(live, now, ''),
    });
    return;
  }
  if (await limited(`vid_${uid}`, 5, DAY_MS)) {
    send(res, 429, { error: 'try_again' });
    return;
  }
  const made = await createMeet(accessToken, uid);
  if (!made) {
    send(res, 400, { error: 'try_again' });
    return;
  }
  const expiresAt = now + VIDEO_MS;
  try {
    const saved = await appendTalk(
      room.ref,
      uid,
      room.snap.get('members'),
      { kind: 'video', meetUrl: made.url, expiresAt },
      talkPreview('video'),
    );
    await pingTalk(saved.other, 'Video', room.id);
    send(res, 200, {
      pairId: room.id,
      message: { id: saved.id, at: saved.at, kind: 'video', from: uid, meetUrl: made.url, expiresAt },
    });
  } catch (err) {
    await deleteEvent(accessToken, made.eventId);
    send(res, err.status || 500, { error: 'try_again' });
  }
}

async function deleteStep(uid, cursor) {
  if (!cursor || cursor === 'posts') {
    const snap = await db.collection('posts').where('uid', '==', uid).limit(15).get();
    for (const doc of snap.docs) await doc.ref.delete();
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
    if (!tokenOk(id, req.query.t)) {
      send(res, 403, { error: 'try_again' });
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
    const [buf] = await bucket.file(filePath).download();
    res.set('Content-Type', contentType);
    res.set('X-Content-Type-Options', 'nosniff');
    res.set('Cache-Control', 'private, max-age=3600');
    res.status(200).send(buf);
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

  if (await talk(req, res, uid, path, bits)) return;

  if (req.method === 'GET' && path === '/v1/me') {
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
    const cursor = typeof req.query.cursor === 'string' ? req.query.cursor : '';
    const step = await deleteStep(uid, cursor);
    send(res, 200, step.done ? { ok: true } : { cursor: step.cursor });
    return;
  }

  if (req.method === 'GET' && path === '/v1/me/media') {
    const media = await db.collection('media').where('uid', '==', uid).get();
    const rows = media.docs
      .filter((d) => d.get('status') === 'ready' && d.get('kind') !== 'voice')
      .map((d) => ({
        id: d.id,
        kind: d.get('kind'),
        url: d.get('url') || fileUrl(req, d.id),
      }));
    send(res, 200, { media: rows });
    return;
  }

  if (req.method === 'GET' && path === '/v1/me/posts') {
    const posts = await db.collection('posts').where('uid', '==', uid).get();
    const me = await db.collection('users').doc(uid).get();
    const blocked = new Set(numberList(me.get('blockedNumbers')));
    let talks = [];
    try {
      talks = await talkInbox(uid);
    } catch (err) {
      console.error(err);
    }
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
          mediaIds: data.mediaIds || [],
          contactsOpen: data.contactsOpen !== false,
          reaches,
        };
      }),
      talks,
    });
    return;
  }

  if (req.method === 'POST' && path === '/v1/me/blocks') {
    const number = typeof req.body?.number === 'string' ? req.body.number.trim() : '';
    if (!/^\+[1-9]\d{7,14}$/.test(number)) {
      send(res, 400, { error: 'try_again' });
      return;
    }
    const posts = await db.collection('posts').where('uid', '==', uid).get();
    const known = posts.docs.some((doc) =>
      Object.values(doc.get('reaches') || {}).some((row) => row && row.number === number),
    );
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
      tx.set(userRef, { blockedNumbers: [...list] }, { merge: true });
    });
    send(res, 200, { blocked });
    return;
  }

  if (req.method === 'GET' && path === '/v1/feed') {
    if (await limited(`feed_${uid}`, 180, 3600_000)) {
      send(res, 429, { error: 'try_again' });
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
    const cats = await db.collection('categories').where('parentId', '==', parentId).get();
    const stamped = new Map();
    await Promise.all(cats.docs.map(async (d) => {
      if (d.get('coverPath') && !d.get('coverUrl')) {
        const url = await stampCover(d);
        if (url) stamped.set(d.id, url);
      }
    }));
    const children = cats.docs
      .map((d) => d.data() && { id: d.id, ...d.data() })
      .filter((c) => c.active !== false)
      .sort((a, b) => (a.sort || 0) - (b.sort || 0));
    const headersOnly = req.query.cards === '0';
    const jobs = headersOnly
      ? []
      : children.filter((c) => resolvedKind(c.id, c) === 'job');
    const grouped = new Map();
    await Promise.all(jobs.map(async (job) => {
      const found = await db.collection('posts')
        .where('categoryId', '==', job.id)
        .where('status', '==', 'active')
        .limit(12)
        .get();
      const list = found.docs.map((doc) => {
        const data = doc.data();
        return { doc, distance: kmBetween(lat, lng, data.lat, data.lng) };
      });
      list.sort((a, b) => a.distance - b.distance);
      grouped.set(job.id, list);
    }));
    const categories = children.map((c) => {
      const kind = resolvedKind(c.id, c);
      const list = kind === 'job'
        ? (grouped.get(c.id) || []).sort((a, b) => a.distance - b.distance).slice(0, 12)
        : [];
      return {
        id: c.id,
        name: nameIn(c.names, lang),
        coverUrl: c.coverUrl || stamped.get(c.id) || (c.coverPath ? fileUrl(req, `cover:${c.id}`) : ''),
        kind,
        posts: list.map((row) => publicView(card(req, row.doc, row.distance), row.distance)),
      };
    });
    const body = { categories };
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
    if (await limited(`detail_${uid}`, 180, 3600_000)) {
      send(res, 429, { error: 'try_again' });
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
    if (await limited(`rev_u_${uid}`, 3, 86400_000)) {
      send(res, 429, { error: 'try_again' });
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
    const doc = await db.collection('posts').doc(bits[2]).get();
    if (!doc.exists || doc.get('uid') !== uid) {
      send(res, 404, { error: 'try_again' });
      return;
    }
    const paused = req.body?.paused !== false;
    await doc.ref.update({ status: paused ? 'paused' : 'active' });
    send(res, 200, { status: paused ? 'paused' : 'active' });
    return;
  }

  if (req.method === 'POST' && bits[0] === 'v1' && bits[1] === 'posts' && bits[2] && bits[3] === 'block') {
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
    if (await limited(`up_${uid}`, 40, 86400_000)) {
      send(res, 429, { error: 'try_again' });
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
    });
    let uploadUrl = '';
    try {
      const origin = req.get('origin') || '';
      const webOrigin = origin === 'https://worky-93fbc.web.app' ||
        origin === 'https://worky-93fbc.firebaseapp.com';
      const [uri] = await bucket.file(objectPath).createResumableUpload({
        metadata: { contentType },
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
    const [buf] = await file.download();
    if (buf.length < 32 || buf.length > MAX_BYTES[doc.get('kind')]) {
      await file.delete({ ignoreNotFound: true });
      await doc.ref.delete();
      send(res, 400, { error: 'try_again' });
      return;
    }
    const accepted = await acceptUpload(doc.get('kind'), buf);
    if (accepted.error) {
      await file.delete({ ignoreNotFound: true });
      await doc.ref.delete();
      send(res, 400, { error: 'try_again' });
      return;
    }
    if (doc.get('kind') === 'voice') {
      await file.setMetadata({
        contentType: accepted.contentType,
        cacheControl: 'private, max-age=3600',
      });
      await doc.ref.update({
        status: 'ready',
        contentType: accepted.contentType,
        bytes: buf.length,
      });
      send(res, 200, { mediaId: id });
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
    await doc.ref.update({
      status: 'ready',
      contentType: accepted.contentType,
      bytes: accepted.rewrite ? accepted.buf.length : buf.length,
      url,
      ...(thumbUrl ? { thumbUrl, thumbPath } : {}),
    });
    send(res, 200, { mediaId: id, url });
    return;
  }

  if ((req.method === 'POST' || req.method === 'PATCH') && (path === '/v1/posts' || (bits[1] === 'posts' && bits[2] && !bits[3]))) {
    if (req.method === 'POST' && (await limited(`post_${uid}`, 20, 86400_000))) {
      send(res, 429, { error: 'try_again' });
      return;
    }
    const saved = await savePost(req, uid, req.method === 'PATCH' ? bits[2] : null);
    send(res, saved.error ? saved.status : 200, saved.error ? { error: 'try_again' } : saved.body);
    return;
  }

  if (req.method === 'DELETE' && bits[0] === 'v1' && bits[1] === 'posts' && bits[2] && !bits[3]) {
    const doc = await db.collection('posts').doc(bits[2]).get();
    if (!doc.exists || doc.get('uid') !== uid) {
      send(res, 404, { error: 'try_again' });
      return;
    }
    await doc.ref.delete();
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
      const made = await writeCategory(req, null);
      send(res, made.error ? 400 : 200, made.error ? { error: made.error } : made.body);
      return;
    }
    if (req.method === 'PATCH' && bits[2] === 'categories' && bits[3] && !bits[4]) {
      const made = await writeCategory(req, bits[3]);
      send(res, made.error ? 400 : 200, made.error ? { error: made.error } : made.body);
      return;
    }
    if (req.method === 'POST' && bits[2] === 'categories' && bits[3] && bits[4] === 'hide') {
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
    updatedAt: Date.now(),
  };
  if (existingId) {
    const doc = await db.collection('posts').doc(existingId).get();
    if (!doc.exists || doc.get('uid') !== uid) return { error: true, status: 404 };
    await doc.ref.update(payload);
    return { body: { id: existingId } };
  }
  const ref = db.collection('posts').doc();
  await ref.set({ ...payload, status: 'active', createdAt: Date.now() });
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
  let coverPath = null;
  let coverUrl = '';
  if (id) {
    const prev = await db.collection('categories').doc(id).get();
    if (!prev.exists) return { error: 'missing' };
    coverPath = prev.get('coverPath');
    coverUrl = prev.get('coverUrl') || '';
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
  const data = { parentId, sort, names: clean, coverPath, coverUrl, active: true, kind };
  if (id) {
    await db.collection('categories').doc(id).set(data, { merge: true });
    return { body: { id } };
  }
  const ref = db.collection('categories').doc();
  await ref.set(data);
  return { body: { id: ref.id } };
}

exports.api = onRequest(
  {
    cors: true,
    memory: '512MiB',
    timeoutSeconds: 60,
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
