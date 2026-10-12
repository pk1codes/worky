const admin = require('firebase-admin');
const { geohash } = require('./lib/geo');
const { shelfId, shelfCard, packShelf } = require('./lib/shelf');

// One-shot, off the request path. Run with: node backfill.js --run
if (!process.argv.includes('--run')) {
  console.log('Pass --run to rebuild shelves and copy user-owned covers.');
  process.exit(0);
}

admin.initializeApp({
  projectId: 'worky-93fbc',
  storageBucket: 'worky-93fbc.firebasestorage.app',
});

const db = admin.firestore();
const bucket = admin.storage().bucket();

function writeGroups(batch, parentId, cell, cards) {
  const placed = packShelf(cards, cell);
  const ref = db.collection('feeds').doc(shelfId(parentId, cell));
  if (!placed.sharded) {
    batch.set(ref, { cards: placed.cards });
    return 1;
  }
  batch.set(ref, { sharded: true });
  let n = 1;
  for (const [finer, list] of placed.groups) {
    const nested = packShelf(list, finer);
    const child = db.collection('feeds').doc(shelfId(parentId, finer));
    if (!nested.sharded) {
      batch.set(child, { cards: nested.cards });
      n += 1;
      continue;
    }
    batch.set(child, { sharded: true });
    n += 1;
    for (const [deep, deepList] of nested.groups) {
      batch.set(db.collection('feeds').doc(shelfId(parentId, deep)), { cards: deepList });
      n += 1;
    }
  }
  return n;
}

async function shelves() {
  const cats = await db.collection('categories').get();
  const parents = new Map(cats.docs.map((doc) => [doc.id, String(doc.get('parentId') || '')]));
  const posts = await db.collection('posts').where('status', '==', 'active').get();
  const groups = new Map();
  for (const doc of posts.docs) {
    const data = doc.data();
    const parentId = typeof data.parentId === 'string' ? data.parentId : parents.get(data.categoryId) || '';
    const cell = data.cell || geohash(data.lat, data.lng, 4);
    const key = shelfId(parentId, cell);
    const list = groups.get(key) || [];
    list.push(shelfCard(doc.id, { ...data, createdAt: data.createdAt || 0 }));
    groups.set(key, list);
  }
  let batch = db.batch();
  let n = 0;
  for (const [key, cards] of groups) {
    const cell = key.slice(key.lastIndexOf('__') + 2);
    const parentId = key.slice(0, key.lastIndexOf('__'));
    n += writeGroups(batch, parentId === 'root' ? '' : parentId, cell, cards);
    if (n >= 400) {
      await batch.commit();
      batch = db.batch();
      n = 0;
    }
  }
  if (n) await batch.commit();
  console.log(`shelves ${groups.size}`);
}

async function covers() {
  const cats = await db.collection('categories').get();
  for (const doc of cats.docs) {
    const path = doc.get('coverPath') || '';
    if (!path.startsWith('users/')) continue;
    const dot = path.lastIndexOf('.');
    const ext = dot === -1 ? 'jpg' : path.slice(dot + 1);
    const dest = `covers/${doc.id}.${ext}`;
    await bucket.file(path).copy(bucket.file(dest));
    const token = require('crypto').randomUUID();
    const contentType = ext === 'png' ? 'image/png' : ext === 'webp' ? 'image/webp' : 'image/jpeg';
    await bucket.file(dest).setMetadata({
      contentType,
      cacheControl: 'public, max-age=31536000, immutable',
      metadata: { firebaseStorageDownloadTokens: token },
    });
    const name = encodeURIComponent(dest);
    const coverUrl = `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${name}?alt=media&token=${token}`;
    await doc.ref.set({ coverPath: dest, coverUrl }, { merge: true });
    console.log(`cover ${doc.id}`);
  }
}

shelves()
  .then(covers)
  .then(() => process.exit(0))
  .catch((err) => {
    console.error(err);
    process.exit(1);
  });
