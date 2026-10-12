const { geohash, ring, closestKm, kmBetween } = require('./geo');

const SHELF_BYTES = 800_000;

function shelfId(parentId, cell) {
  return `${parentId || 'root'}__${cell}`;
}

function shelfCard(id, data) {
  return {
    id,
    categoryId: data.categoryId,
    lat: data.lat,
    lng: data.lng,
    createdAt: data.createdAt || 0,
    langs: data.langs || [],
    thumbUrl: data.thumbUrl || '',
    posterUrl: data.posterUrl || '',
    hasVideo: !!data.hasVideo,
  };
}

function packShelf(cards, cell, limit = SHELF_BYTES) {
  const body = { cards };
  if (Buffer.byteLength(JSON.stringify(body)) <= limit) return { sharded: false, cards };
  const groups = new Map();
  for (const card of cards) {
    const finer = geohash(card.lat, card.lng, cell.length + 1);
    const list = groups.get(finer) || [];
    list.push(card);
    groups.set(finer, list);
  }
  return { sharded: true, groups };
}

function wantNeighbor(cards, jobIds, lat, lng, neighborHash) {
  const edge = closestKm(lat, lng, neighborHash);
  const ids = jobIds.length ? jobIds : [...new Set(cards.map((card) => card.categoryId))];
  for (const id of ids) {
    const rows = cards.filter((card) => card.categoryId === id);
    if (rows.length < 12) return true;
    rows.sort(
      (a, b) => kmBetween(lat, lng, a.lat, a.lng) - kmBetween(lat, lng, b.lat, b.lng),
    );
    const far = rows[11];
    if (edge < kmBetween(lat, lng, far.lat, far.lng)) return true;
  }
  return false;
}

function capBlocks(list, max = 50) {
  const items = [...list];
  if (items.length <= max) return items;
  return items.slice(items.length - max);
}

module.exports = {
  SHELF_BYTES,
  shelfId,
  shelfCard,
  packShelf,
  wantNeighbor,
  ring,
  capBlocks,
};
