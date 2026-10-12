const { iso1A2Code } = require('@rapideditor/country-coder');

const BASE = '0123456789bcdefghjkmnpqrstuvwxyz';
const LANGS = ['hi', 'en', 'ta', 'te', 'kn', 'ml', 'mr', 'bn', 'gu', 'pa', 'ur', 'or'];

function coarse(n) {
  return Math.round(Number(n) * 1000) / 1000;
}

const NEIGH = {
  n: ['p0r21436x8zb9dcf5h7kjnmqesgutwvy', 'bc01fg45238967deuvhjyznpkmstqrwx'],
  s: ['14365h7k9dcfesgujnmqp0r2twvyx8zb', '238967debc01fg45kmstqrwxuvhjyznp'],
  e: ['bc01fg45238967deuvhjyznpkmstqrwx', 'p0r21436x8zb9dcf5h7kjnmqesgutwvy'],
  w: ['238967debc01fg45kmstqrwxuvhjyznp', '14365h7k9dcfesgujnmqp0r2twvyx8zb'],
};
const BORDER = {
  n: ['prxz', 'bcfguvyz'],
  s: ['028b', '0145hjnp'],
  e: ['bcfguvyz', 'prxz'],
  w: ['0145hjnp', '028b'],
};

function adjacent(hash, dir) {
  const type = hash.length % 2;
  let parent = hash.slice(0, -1);
  const last = hash[hash.length - 1];
  if (BORDER[dir][type].includes(last) && parent) parent = adjacent(parent, dir);
  return parent + BASE[NEIGH[dir][type].indexOf(last)];
}

function ring(hash) {
  const n = adjacent(hash, 'n');
  const s = adjacent(hash, 's');
  const e = adjacent(hash, 'e');
  const w = adjacent(hash, 'w');
  return [n, s, e, w, adjacent(n, 'e'), adjacent(s, 'e'), adjacent(n, 'w'), adjacent(s, 'w')];
}

function hashBounds(hash) {
  let even = true;
  const lat = [-90, 90];
  const lng = [-180, 180];
  for (const ch of hash) {
    const idx = BASE.indexOf(ch);
    for (let bit = 4; bit >= 0; bit -= 1) {
      const up = (idx >> bit) & 1;
      if (even) {
        const mid = (lng[0] + lng[1]) / 2;
        if (up) lng[0] = mid;
        else lng[1] = mid;
      } else {
        const mid = (lat[0] + lat[1]) / 2;
        if (up) lat[0] = mid;
        else lat[1] = mid;
      }
      even = !even;
    }
  }
  return { south: lat[0], north: lat[1], west: lng[0], east: lng[1] };
}

function closestKm(lat, lng, hash) {
  const box = hashBounds(hash);
  const cLat = Math.min(box.north, Math.max(box.south, lat));
  const cLng = Math.min(box.east, Math.max(box.west, lng));
  return kmBetween(lat, lng, cLat, cLng);
}

function geohash(lat, lng, precision = 4) {
  let idx = 0;
  let bit = 0;
  let even = true;
  let hash = '';
  const latR = [-90, 90];
  const lngR = [-180, 180];
  while (hash.length < precision) {
    if (even) {
      const mid = (lngR[0] + lngR[1]) / 2;
      if (lng >= mid) {
        idx = idx * 2 + 1;
        lngR[0] = mid;
      } else {
        idx *= 2;
        lngR[1] = mid;
      }
    } else {
      const mid = (latR[0] + latR[1]) / 2;
      if (lat >= mid) {
        idx = idx * 2 + 1;
        latR[0] = mid;
      } else {
        idx *= 2;
        latR[1] = mid;
      }
    }
    even = !even;
    bit += 1;
    if (bit === 5) {
      hash += BASE[idx];
      bit = 0;
      idx = 0;
    }
  }
  return hash;
}

function kmBetween(aLat, aLng, bLat, bLng) {
  const r = 6371;
  const dLat = ((bLat - aLat) * Math.PI) / 180;
  const dLng = ((bLng - aLng) * Math.PI) / 180;
  const s =
    Math.sin(dLat / 2) ** 2 +
    Math.cos((aLat * Math.PI) / 180) *
      Math.cos((bLat * Math.PI) / 180) *
      Math.sin(dLng / 2) ** 2;
  return 2 * r * Math.asin(Math.min(1, Math.sqrt(s)));
}

function band(km) {
  if (km < 2) return 'near';
  if (km < 15) return 'mid';
  return 'far';
}

function daysAgo(ms) {
  return Math.max(0, Math.floor((Date.now() - ms) / 86400000));
}

function publicPoint(lat, lng) {
  const snap = (n) => Math.round(Number(n) * 50) / 50;
  return { lat: snap(lat), lng: snap(lng) };
}

function publicKm(km) {
  return Math.max(2, Math.round(Number(km)));
}

function isoCountry(lat, lng) {
  const latN = Number(lat);
  const lngN = Number(lng);
  if (!Number.isFinite(latN) || !Number.isFinite(lngN)) return null;
  if (Math.abs(latN) > 90 || Math.abs(lngN) > 180) return null;
  const code = iso1A2Code([lngN, latN], {});
  if (typeof code !== 'string') return null;
  const iso = code.toUpperCase();
  return /^[A-Z]{2}$/.test(iso) ? iso : null;
}

module.exports = {
  BASE,
  LANGS,
  coarse,
  geohash,
  adjacent,
  ring,
  hashBounds,
  closestKm,
  kmBetween,
  band,
  daysAgo,
  publicPoint,
  publicKm,
  isoCountry,
};
