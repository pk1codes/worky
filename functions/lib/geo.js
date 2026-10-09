const BASE = '0123456789bcdefghjkmnpqrstuvwxyz';
const LANGS = ['hi', 'en', 'ta', 'te', 'kn', 'ml', 'mr', 'bn', 'gu', 'pa', 'ur', 'or'];

function coarse(n) {
  return Math.round(Number(n) * 1000) / 1000;
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

module.exports = { BASE, LANGS, coarse, geohash, kmBetween, band, daysAgo };
