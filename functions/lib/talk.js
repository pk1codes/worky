const DAY_MS = 86_400_000;
const VIDEO_MS = 2 * 60 * 60 * 1000;
const TEXT_MAX = 500;

function pairId(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string' || a === b) return '';
  if (!/^[A-Za-z0-9]{6,128}$/.test(a) || !/^[A-Za-z0-9]{6,128}$/.test(b)) return '';
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

function googleMatch(sub, providerData) {
  const rows = Array.isArray(providerData) ? providerData : [];
  return rows.some((row) => row && row.providerId === 'google.com' && row.uid === sub && sub);
}

function meetBody(now, requestId) {
  return {
    summary: 'Worky Talk',
    start: { dateTime: new Date(now).toISOString() },
    end: { dateTime: new Date(now + VIDEO_MS).toISOString() },
    conferenceData: {
      createRequest: {
        requestId,
        conferenceSolutionKey: { type: 'hangoutsMeet' },
      },
    },
  };
}

function meetUrl(event) {
  const points = event && event.conferenceData && event.conferenceData.entryPoints;
  const list = Array.isArray(points) ? points : [];
  const video = list.find((row) => row && row.entryPointType === 'video' && typeof row.uri === 'string');
  const raw = (video && video.uri) || (event && typeof event.hangoutLink === 'string' ? event.hangoutLink : '');
  const url = String(raw).split('?')[0];
  if (!/^https:\/\/meet\.google\.com\/[a-z0-9-]{5,64}$/i.test(url)) return '';
  return url;
}

function viewMessage(msg, now, voiceUrl) {
  const row = { id: msg.id, from: msg.from, at: msg.at, kind: msg.kind };
  if (msg.kind === 'text') row.text = msg.text || '';
  if (msg.kind === 'voice') {
    row.url = voiceUrl || '';
    row.durMs = msg.durMs || 0;
  }
  if (msg.kind === 'video') {
    row.expiresAt = msg.expiresAt || 0;
    if (msg.meetUrl && msg.expiresAt > now) row.meetUrl = msg.meetUrl;
  }
  return row;
}

module.exports = {
  DAY_MS,
  VIDEO_MS,
  TEXT_MAX,
  pairId,
  pairMembers,
  cleanText,
  googleMatch,
  meetBody,
  meetUrl,
  viewMessage,
};
