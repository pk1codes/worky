const CONTAINERS = new Set(['moov', 'trak', 'mdia', 'minf', 'stbl']);

function walkBoxes(buf, start, end, visit) {
  let o = start;
  while (o + 8 <= end) {
    let size = buf.readUInt32BE(o);
    const type = buf.toString('latin1', o + 4, o + 8);
    let header = 8;
    if (size === 1) {
      if (o + 16 > end) break;
      size = Number(buf.readBigUInt64BE(o + 8));
      header = 16;
    } else if (size === 0) {
      size = end - o;
    }
    if (!Number.isFinite(size) || size < header || o + size > end) break;
    const payload = o + header;
    visit(type, payload, o + size);
    if (CONTAINERS.has(type)) walkBoxes(buf, payload, o + size, visit);
    o += size;
  }
}

function parseMvhd(buf, start, end) {
  if (start + 20 > end) return null;
  const version = buf[start];
  if (version === 0 && start + 20 <= end) {
    const timescale = buf.readUInt32BE(start + 12);
    const duration = buf.readUInt32BE(start + 16);
    if (!timescale) return null;
    return duration / timescale;
  }
  if (version === 1 && start + 32 <= end) {
    const timescale = buf.readUInt32BE(start + 20);
    const duration = Number(buf.readBigUInt64BE(start + 24));
    if (!timescale) return null;
    return duration / timescale;
  }
  return null;
}

function parseTkhd(buf, start, end) {
  const version = buf[start];
  const widthAt = version === 1 ? start + 88 : start + 76;
  if (widthAt + 8 > end) return null;
  const width = buf.readUInt32BE(widthAt) / 65536;
  const height = buf.readUInt32BE(widthAt + 4) / 65536;
  return { width, height };
}

function parseMp4(buf) {
  if (buf.length < 12 || buf.toString('latin1', 4, 8) !== 'ftyp') {
    return null;
  }
  let duration = null;
  let width = 0;
  let height = 0;
  let tracks = 0;
  walkBoxes(buf, 0, buf.length, (type, start, end) => {
    if (type === 'mvhd' && duration == null) duration = parseMvhd(buf, start, end);
    if (type === 'trak') tracks += 1;
    if (type === 'tkhd') {
      const box = parseTkhd(buf, start, end);
      if (box && box.width * box.height > width * height) {
        width = box.width;
        height = box.height;
      }
    }
  });
  if (duration == null) return null;
  return { duration, width, height, tracks };
}

function parseWav(buf) {
  if (buf.length < 44) return null;
  if (buf.toString('latin1', 0, 4) !== 'RIFF') return null;
  if (buf.toString('latin1', 8, 12) !== 'WAVE') return null;
  let o = 12;
  let byteRate = 0;
  let dataSize = 0;
  while (o + 8 <= buf.length) {
    const id = buf.toString('latin1', o, o + 4);
    const size = buf.readUInt32LE(o + 4);
    if (id === 'fmt ' && o + 8 + 16 <= buf.length) byteRate = buf.readUInt32LE(o + 16);
    if (id === 'data') {
      dataSize = size;
      break;
    }
    o += 8 + size + (size % 2);
  }
  if (!byteRate || !dataSize) return null;
  return { duration: dataSize / byteRate, tracks: 1 };
}

const MPEG1_L3 = [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 0];
const MPEG1_RATES = [44100, 48000, 32000];

function parseMp3(buf) {
  let o = 0;
  if (buf.toString('latin1', 0, 3) === 'ID3' && buf.length >= 10) {
    const size =
      ((buf[6] & 127) << 21) |
      ((buf[7] & 127) << 14) |
      ((buf[8] & 127) << 7) |
      (buf[9] & 127);
    o = 10 + size;
  }
  let samples = 0;
  let rate = 0;
  let frames = 0;
  while (o + 4 < buf.length && frames < 40000) {
    if (buf[o] !== 0xff || (buf[o + 1] & 0xe0) !== 0xe0) {
      o += 1;
      continue;
    }
    const version = (buf[o + 1] >> 3) & 3;
    const layer = (buf[o + 1] >> 1) & 3;
    const br = (buf[o + 2] >> 4) & 15;
    const sr = (buf[o + 2] >> 2) & 3;
    if (version !== 3 || layer !== 1 || br === 0 || br === 15 || sr === 3) {
      o += 1;
      continue;
    }
    const bitrate = MPEG1_L3[br] * 1000;
    const sampleRate = MPEG1_RATES[sr];
    const pad = (buf[o + 2] >> 1) & 1;
    const frameLen = Math.floor((144 * bitrate) / sampleRate) + pad;
    if (frameLen < 24 || o + frameLen > buf.length + 4) {
      o += 1;
      continue;
    }
    samples += 1152;
    rate = sampleRate;
    frames += 1;
    o += frameLen;
  }
  if (!frames || !rate) return null;
  return { duration: samples / rate, tracks: 1 };
}

function sniff(buf) {
  if (buf.length >= 3 && buf[0] === 0xff && buf[1] === 0xd8 && buf[2] === 0xff) return 'jpeg';
  if (buf.length >= 8 && buf[0] === 0x89 && buf.toString('latin1', 1, 4) === 'PNG') return 'png';
  if (
    buf.length >= 12 &&
    buf.toString('latin1', 0, 4) === 'RIFF' &&
    buf.toString('latin1', 8, 12) === 'WEBP'
  ) {
    return 'webp';
  }
  if (buf.length >= 12 && buf.toString('latin1', 4, 8) === 'ftyp') return 'mp4';
  if (buf.length >= 12 && buf.toString('latin1', 0, 4) === 'RIFF' && buf.toString('latin1', 8, 12) === 'WAVE') {
    return 'wav';
  }
  if (buf.length >= 3 && buf.toString('latin1', 0, 3) === 'ID3') return 'mp3';
  if (buf.length >= 2 && buf[0] === 0xff && (buf[1] & 0xe0) === 0xe0) return 'mp3';
  return null;
}

const KIND_TYPE = {
  image: new Set(['jpeg', 'png', 'webp']),
  video: new Set(['mp4']),
  audio: new Set(['mp3', 'wav', 'mp4']),
};

const SERVE_TYPE = {
  image: 'image/jpeg',
  video: 'video/mp4',
  audio: 'audio/mpeg',
};

function limitsFor(kind, info) {
  if (kind === 'image') return null;
  if (!info || !Number.isFinite(info.duration)) return 'unreadable';
  if (info.tracks > 4) return 'tracks';
  if (kind === 'video') {
    if (info.duration > 30) return 'duration';
    if (info.width > 1280 || info.height > 1280) return 'dimensions';
    return null;
  }
  if (info.duration > 60) return 'duration';
  return null;
}

const THUMB_EDGE = 480;

function needsThumb(width, height) {
  return width > THUMB_EDGE || height > THUMB_EDGE;
}

function extFor(kind, contentType) {
  if (kind === 'image' && contentType === 'image/webp') return 'webp';
  if (kind === 'image' && contentType === 'image/jpeg') return 'jpg';
  if (kind === 'image' && contentType === 'image/png') return 'png';
  if (kind === 'video' && contentType === 'video/mp4') return 'mp4';
  if (kind === 'audio' && (contentType === 'audio/mp4' || contentType === 'audio/aac')) return 'm4a';
  if (kind === 'audio' && contentType === 'audio/mpeg') return 'mp3';
  return null;
}

async function clipMp4(size, read) {
  let offset = 0;
  let ftyp = null;
  let moov = null;
  while (offset + 8 <= size && (ftyp == null || moov == null)) {
    const head = await read(offset, Math.min(size - 1, offset + 15));
    if (!head || head.length < 8) return null;
    let boxSize = head.readUInt32BE(0);
    let header = 8;
    if (boxSize === 1) {
      if (head.length < 16) return null;
      boxSize = Number(head.readBigUInt64BE(8));
      header = 16;
    } else if (boxSize === 0) boxSize = size - offset;
    if (!Number.isFinite(boxSize) || boxSize < header || offset + boxSize > size) return null;
    const type = head.toString('latin1', 4, 8);
    if (type === 'ftyp' || type === 'moov') {
      if (boxSize > 2_000_000) return null;
      const box = await read(offset, offset + boxSize - 1);
      if (!box || box.length < boxSize) return null;
      if (type === 'ftyp') ftyp = box.subarray(0, boxSize);
      else moov = box.subarray(0, boxSize);
    }
    offset += boxSize;
  }
  if (!ftyp || !moov) return null;
  return Buffer.concat([ftyp, moov]);
}

function publicUrl(bucketName, objectPath, token) {
  const name = encodeURIComponent(objectPath);
  return `https://firebasestorage.googleapis.com/v0/b/${bucketName}/o/${name}?alt=media&token=${token}`;
}

module.exports = {
  parseMp4,
  parseWav,
  parseMp3,
  sniff,
  KIND_TYPE,
  SERVE_TYPE,
  limitsFor,
  extFor,
  clipMp4,
  publicUrl,
  THUMB_EDGE,
  needsThumb,
};
