const test = require('node:test');
const assert = require('node:assert');
const { allow, clientIp, overCap } = require('../lib/gate');

test('a short burst is allowed and the next call waits', () => {
  const key = `burst-${Math.random()}`;
  assert.equal(allow(key, 2, 1000, 0).ok, true);
  assert.equal(allow(key, 2, 1000, 10).ok, true);
  const blocked = allow(key, 2, 1000, 20);
  assert.equal(blocked.ok, false);
  assert.ok(blocked.retryAfter >= 1);
  assert.equal(allow(key, 2, 1000, 1001).ok, true);
});

test('one route does not spend another route budget', () => {
  const stamp = 5_000;
  assert.equal(allow(`a-${stamp}`, 1, 1000, stamp).ok, true);
  assert.equal(allow(`a-${stamp}`, 1, 1000, stamp + 1).ok, false);
  assert.equal(allow(`b-${stamp}`, 1, 1000, stamp + 1).ok, true);
});

test('the client address is the hop appended by the proxy', () => {
  assert.equal(clientIp('1.1.1.1, 2.2.2.2', '9.9.9.9'), '2.2.2.2');
  assert.equal(clientIp('  8.8.8.8  ', ''), '8.8.8.8');
  assert.equal(clientIp('', '9.9.9.9'), '9.9.9.9');
  assert.equal(clientIp(undefined, ''), '0');
});

test('a full window rejects with no further write', () => {
  assert.equal(overCap(3, 5_000, 1_000, 3), true);
  assert.equal(overCap(2, 5_000, 1_000, 3), false);
  assert.equal(overCap(3, 500, 1_000, 3), false);
});
