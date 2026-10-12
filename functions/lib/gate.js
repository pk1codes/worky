const buckets = new Map();

function allow(key, max, windowMs, now = Date.now()) {
  let list = buckets.get(key) || [];
  const start = now - windowMs;
  let i = 0;
  while (i < list.length && list[i] <= start) i += 1;
  if (i) list = list.slice(i);
  if (list.length >= max) {
    buckets.delete(key);
    buckets.set(key, list);
    const retryAfter = Math.max(1, Math.ceil((list[0] + windowMs - now) / 1000));
    return { ok: false, retryAfter };
  }
  list.push(now);
  buckets.delete(key);
  buckets.set(key, list);
  if (buckets.size > 8000) buckets.delete(buckets.keys().next().value);
  return { ok: true, retryAfter: 0 };
}

function clientIp(header, fallback) {
  const parts = String(header || '')
    .split(',')
    .map((part) => part.trim())
    .filter(Boolean);
  if (parts.length) return parts[parts.length - 1];
  return fallback || '0';
}

function overCap(n, reset, now, max) {
  return reset > now && n >= max;
}

module.exports = { allow, clientIp, overCap };
