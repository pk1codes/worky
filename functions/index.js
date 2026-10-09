const crypto = require('crypto');
const admin = require('firebase-admin');
const { onRequest } = require('firebase-functions/v2/https');
const sharp = require('sharp');
const { LANGS, coarse, geohash, kmBetween, band, daysAgo } = require('./lib/geo');
const { parseMp4, parseWav, parseMp3, sniff, KIND_TYPE, SERVE_TYPE, limitsFor } = require('./lib/media');

admin.initializeApp({
  projectId: 'worky-93fbc',
  storageBucket: 'worky-93fbc.firebasestorage.app',
});

const db = admin.firestore();
const bucket = admin.storage().bucket();
const FILE_KEY = process.env.FILE_TOKEN_KEY || 'worky-local-file-key';
const MAX_BYTES = { image: 8_000_000, video: 20_000_000, audio: 8_000_000 };

const NAMES = {
  work: {
    en: 'Work', hi: 'काम', ta: 'வேலை', te: 'పని', kn: 'ಕೆಲಸ', ml: 'ജോലി',
    mr: 'काम', bn: 'কাজ', gu: 'કામ', pa: 'ਕੰਮ', ur: 'کام', or: 'କାମ',
  },
  home: {
    en: 'Home', hi: 'घर', ta: 'வீடு', te: 'ఇల్లు', kn: 'ಮನೆ', ml: 'വീട്',
    mr: 'घर', bn: 'বাড়ি', gu: 'ઘર', pa: 'ਘਰ', ur: 'گھر', or: 'ଘର',
  },
  paint: {
    en: 'Paint', hi: 'रंग', ta: 'வண்ணம்', te: 'రంగు', kn: 'ಬಣ್ಣ', ml: 'ചായം',
    mr: 'रंग', bn: 'রং', gu: 'રંગ', pa: 'ਰੰਗ', ur: 'رنگ', or: 'ରଙ୍ଗ',
  },
  carry: {
    en: 'Carry', hi: 'ढोना', ta: 'சுமை', te: 'మోత', kn: 'ಹೊರೆ', ml: 'ചുമട്',
    mr: 'ओझे', bn: 'বওয়া', gu: 'ઉપાડ', pa: 'ਭਾਰ', ur: 'بوجھ', or: 'ବୋଝ',
  },
};

const SEED = [
  { id: 'work', parentId: '', sort: 0, color: '#E07A3D', kind: 'parent' },
  { id: 'home', parentId: '', sort: 1, color: '#2F6FED', kind: 'parent' },
  { id: 'paint', parentId: 'work', sort: 0, color: '#E03D7A', kind: 'job' },
  { id: 'carry', parentId: 'work', sort: 1, color: '#1F9D62', kind: 'job' },
];

function tokenFor(id, ms = 3600_000) {
  const exp = Date.now() + ms;
  const sig = crypto.createHmac('sha256', FILE_KEY).update(`${id}.${exp}`).digest('base64url');
  return `${exp}.${sig}`;
}

function tokenOk(id, token) {
  const parts = String(token || '').split('.');
  if (parts.length !== 2) return false;
  const [exp, sig] = parts;
  if (!/^\d+$/.test(exp) || Number(exp) < Date.now()) return false;
  const expect = crypto.createHmac('sha256', FILE_KEY).update(`${id}.${exp}`).digest('base64url');
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

function clientIp(req) {
  const fwd = req.get('x-forwarded-for') || '';
  return (fwd.split(',')[0] || req.ip || '0').trim().slice(0, 64);
}

function nameIn(names, lang) {
  if (names && names[lang]) return names[lang];
  if (names && names.en) return names.en;
  return '';
}

function resolvedKind(id, data) {
  const stored = data && data.kind;
  if (stored === 'parent' || stored === 'job') return stored;
  if (id === 'home' || id === 'work') return 'parent';
  if (id === 'paint' || id === 'carry') return 'job';
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
      await bucket.file(path).save(png, { contentType: 'image/png', resumable: false });
      await db.collection('categories').doc(row.id).set({
        parentId: row.parentId,
        sort: row.sort,
        active: true,
        kind: row.kind,
        names: NAMES[row.id],
        coverPath: path,
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

async function acceptUpload(kind, buf) {
  const sniffed = sniff(buf);
  if (!sniffed || !KIND_TYPE[kind].has(sniffed)) return { error: 'type' };
  if (kind === 'image') {
    try {
      const img = sharp(buf, { failOn: 'error', limitInputPixels: 12_000_000 });
      const meta = await img.metadata();
      const pixels = (meta.width || 0) * (meta.height || 0);
      if (!pixels || pixels > 12_000_000) return { error: 'pixels' };
      const out = await img
        .rotate()
        .resize({ width: 1600, height: 1600, fit: 'inside', withoutEnlargement: true })
        .jpeg({ quality: 80 })
        .toBuffer();
      return { buf: out, contentType: 'image/jpeg' };
    } catch (_) {
      return { error: 'type' };
    }
  }
  const info = sniffed === 'mp4' ? parseMp4(buf) : sniffed === 'wav' ? parseWav(buf) : parseMp3(buf);
  const problem = limitsFor(kind, info);
  if (problem) return { error: problem };
  const contentType = kind === 'video' ? 'video/mp4' : sniffed === 'wav' ? 'audio/wav' : 'audio/mpeg';
  return { buf, contentType };
}

function card(req, doc, distanceKm) {
  const data = doc.data();
  return {
    id: doc.id,
    posterUrl: data.posterPath ? fileUrl(req, `poster:${doc.id}`) : '',
    daysAgo: daysAgo(data.createdAt || Date.now()),
    band: band(distanceKm),
    langs: data.langs || [],
    hasVideo: !!data.hasVideo,
    lat: data.lat,
    lng: data.lng,
    categoryId: data.categoryId,
    status: data.status,
  };
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
  const ip = clientIp(req);

  try {
    await seed();
  } catch (err) {
    console.error(err);
    send(res, 500, { error: 'try_again' });
    return;
  }

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
    const posts = await db.collection('posts').where('uid', '==', uid).get();
    for (const doc of posts.docs) await doc.ref.delete();
    const media = await db.collection('media').where('uid', '==', uid).get();
    for (const doc of media.docs) {
      if (doc.get('path')) await bucket.file(doc.get('path')).delete({ ignoreNotFound: true });
      await doc.ref.delete();
    }
    await db.collection('users').doc(uid).delete();
    await admin.auth().deleteUser(uid);
    send(res, 200, { ok: true });
    return;
  }

  if (req.method === 'GET' && path === '/v1/me/media') {
    const media = await db.collection('media').where('uid', '==', uid).get();
    const rows = media.docs
      .filter((d) => d.get('status') === 'ready')
      .map((d) => ({
        id: d.id,
        kind: d.get('kind'),
        url: fileUrl(req, d.id),
      }));
    send(res, 200, { media: rows });
    return;
  }

  if (req.method === 'GET' && path === '/v1/me/posts') {
    const posts = await db.collection('posts').where('uid', '==', uid).get();
    send(res, 200, {
      posts: posts.docs.map((doc) => {
        const data = doc.data();
        return {
          ...card(req, doc, 0),
          mine: true,
          status: data.status,
          langs: data.langs || [],
          categoryId: data.categoryId,
          mediaIds: data.mediaIds || [],
        };
      }),
    });
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
    const cell = geohash(lat, lng, 4);
    const cats = await db.collection('categories').where('parentId', '==', parentId).get();
    const children = cats.docs
      .map((d) => d.data() && { id: d.id, ...d.data() })
      .filter((c) => c.active !== false)
      .sort((a, b) => (a.sort || 0) - (b.sort || 0));
    const childIds = new Set(children.map((c) => c.id));
    const found = await db.collection('posts').where('cell', '==', cell).where('status', '==', 'active').limit(200).get();
    const grouped = new Map();
    for (const doc of found.docs) {
      const data = doc.data();
      if (!childIds.has(data.categoryId)) continue;
      const distance = kmBetween(lat, lng, data.lat, data.lng);
      const list = grouped.get(data.categoryId) || [];
      list.push({ doc, distance });
      grouped.set(data.categoryId, list);
    }
    const categories = children.map((c) => {
      const kind = resolvedKind(c.id, c);
      const list = kind === 'job'
        ? (grouped.get(c.id) || []).sort((a, b) => a.distance - b.distance).slice(0, 12)
        : [];
      return {
        id: c.id,
        name: nameIn(c.names, lang),
        coverUrl: c.coverPath ? fileUrl(req, `cover:${c.id}`) : '',
        kind,
        posts: list.map((row) => card(req, row.doc, row.distance)),
      };
    });
    const body = { categories };
    const etag = `"${crypto.createHash('sha1').update(JSON.stringify(body)).digest('hex')}"`;
    res.set('ETag', etag);
    res.set('Cache-Control', 'private, max-age=60');
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
    const media = [];
    for (const id of data.mediaIds || []) {
      const m = await db.collection('media').doc(id).get();
      if (!m.exists || m.get('status') !== 'ready') continue;
      media.push({ id, kind: m.get('kind'), url: fileUrl(req, id) });
    }
    send(res, 200, {
      id: doc.id,
      categoryId: data.categoryId,
      daysAgo: daysAgo(data.createdAt),
      band: 'near',
      langs: data.langs || [],
      status: data.status,
      lat: data.lat,
      lng: data.lng,
      mine,
      media,
      mediaIds: mine ? data.mediaIds || [] : undefined,
    });
    return;
  }

  if (req.method === 'POST' && bits[0] === 'v1' && bits[1] === 'posts' && bits[2] && bits[3] === 'reveal') {
    const postId = bits[2];
    const blocked =
      (await limited(`rev_u_${uid}`, 30, 86400_000)) ||
      (await limited(`rev_p_${uid}_${postId}`, 5, 86400_000)) ||
      (await limited(`rev_i_${ip.replace(/[^\w]/g, '_')}`, 40, 86400_000));
    if (blocked) {
      send(res, 429, { error: 'try_again' });
      return;
    }
    const channel = req.body?.channel;
    if (!['whatsapp', 'phone', 'gmail'].includes(channel)) {
      send(res, 400, { error: 'try_again' });
      return;
    }
    const doc = await db.collection('posts').doc(postId).get();
    if (!doc.exists || doc.get('status') !== 'active' || doc.get('uid') === uid) {
      send(res, 404, { error: 'try_again' });
      return;
    }
    const owner = await db.collection('users').doc(doc.get('uid')).get();
    const authUser = await admin.auth().getUser(doc.get('uid'));
    let url = '';
    if (channel === 'gmail') {
      const email = authUser.email || '';
      if (!email) {
        send(res, 404, { error: 'try_again' });
        return;
      }
      url = `mailto:${email}`;
    } else {
      const number = owner.exists ? owner.get('whatsapp') || '' : '';
      if (!number) {
        send(res, 404, { error: 'try_again' });
        return;
      }
      const digits = number.replace(/\D/g, '');
      url = channel === 'whatsapp' ? `https://wa.me/${digits}` : `tel:${number}`;
    }
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

  if (req.method === 'POST' && path === '/v1/media/upload-url') {
    if (await limited(`up_${uid}`, 40, 86400_000)) {
      send(res, 429, { error: 'try_again' });
      return;
    }
    const kind = req.body?.kind;
    const bytes = Number(req.body?.bytes || 0);
    if (!MAX_BYTES[kind] || bytes < 32 || bytes > MAX_BYTES[kind]) {
      send(res, 400, { error: 'try_again' });
      return;
    }
    const id = crypto.randomBytes(12).toString('hex');
    await db.collection('media').doc(id).set({
      uid,
      kind,
      status: 'pending',
      bytes,
      createdAt: Date.now(),
    });
    send(res, 200, {
      mediaId: id,
      uploadUrl: `${apiRoot(req)}/v1/media/raw/${id}?t=${tokenFor(id, 600_000)}`,
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
    const buf = Buffer.isBuffer(req.rawBody) && req.rawBody.length
      ? req.rawBody
      : Buffer.isBuffer(req.body)
        ? req.body
        : Buffer.alloc(0);
    if (buf.length < 32 || buf.length > MAX_BYTES[doc.get('kind')]) {
      await doc.ref.delete();
      send(res, 400, { error: 'try_again' });
      return;
    }
    const accepted = await acceptUpload(doc.get('kind'), buf);
    if (accepted.error) {
      await doc.ref.delete();
      send(res, 400, { error: 'try_again' });
      return;
    }
    const ext = accepted.contentType === 'image/jpeg' ? 'jpg' : accepted.contentType === 'video/mp4' ? 'mp4' : accepted.contentType === 'audio/wav' ? 'wav' : 'mp3';
    const path = `users/${uid}/${id}.${ext}`;
    await bucket.file(path).save(accepted.buf, {
      contentType: accepted.contentType,
      resumable: false,
      metadata: { contentType: accepted.contentType },
    });
    await doc.ref.update({
      status: 'ready',
      path,
      contentType: accepted.contentType,
      bytes: accepted.buf.length,
    });
    send(res, 200, { mediaId: id, url: fileUrl(req, id) });
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
      send(res, 200, {
        categories: cats.docs.map((d) => ({
          id: d.id,
          ...d.data(),
          kind: resolvedKind(d.id, d.data()),
          coverUrl: fileUrl(req, `cover:${d.id}`),
        })),
      });
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
  let hasVideo = false;
  for (const id of ids) {
    if (typeof id !== 'string') return null;
    const doc = await db.collection('media').doc(id).get();
    if (!doc.exists || doc.get('uid') !== uid || doc.get('status') !== 'ready') return null;
    const kind = doc.get('kind');
    if (kind === 'image') images += 1;
    if (kind === 'video') {
      videos += 1;
      hasVideo = true;
    }
    if (kind === 'audio') audios += 1;
    if (kind === 'image' && !posterPath) posterPath = doc.get('path');
    out.push(id);
  }
  if (images < 1 || images > 5 || videos > 5 || audios > 5) return null;
  return { ids: out, posterPath, hasVideo };
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
  if (id) {
    const prev = await db.collection('categories').doc(id).get();
    if (!prev.exists) return { error: 'missing' };
    coverPath = prev.get('coverPath');
  }
  if (req.body?.coverMediaId) {
    const media = await db.collection('media').doc(String(req.body.coverMediaId)).get();
    if (!media.exists || media.get('kind') !== 'image' || media.get('status') !== 'ready') {
      return { error: 'cover' };
    }
    coverPath = media.get('path');
  }
  if (!coverPath) return { error: 'cover' };
  const data = { parentId, sort, names: clean, coverPath, active: true, kind };
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
