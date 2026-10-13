const DAY_MS = 86_400_000;
const TEXT_MAX = 500;

function pairId(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string' || a === b) return '';
  if (!/^[A-Za-z0-9-]{6,128}$/.test(a) || !/^[A-Za-z0-9-]{6,128}$/.test(b)) return '';
  return [a, b].sort().join('_');
}

function pairMembers(id, uid) {
  const parts = String(id || '').split('_');
  if (parts.length !== 2 || !parts.includes(uid)) return null;
  if (!pairId(parts[0], parts[1])) return null;
  return parts;
}

function cleanText(value) {
  const text = String(value || '').trim();
  if (!text || text.length > TEXT_MAX) return '';
  return text;
}

function viewMessage(msg, now, voiceUrl) {
  const row = { id: msg.id, from: msg.from, at: msg.at, kind: msg.kind };
  if (msg.kind === 'text') row.text = msg.text || '';
  if (msg.kind === 'voice') {
    row.url = voiceUrl || '';
    row.durMs = msg.durMs || 0;
  }
  return row;
}

module.exports = {
  DAY_MS,
  TEXT_MAX,
  pairId,
  pairMembers,
  cleanText,
  viewMessage,
};
