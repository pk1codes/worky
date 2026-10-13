const test = require('node:test');
const assert = require('node:assert');
const { pairId, pairMembers, cleanText, viewMessage } = require('../lib/talk');

test('a pair id is the two accounts sorted once', () => {
  assert.equal(pairId('bbbbbb', 'aaaaaa'), 'aaaaaa_bbbbbb');
  assert.equal(pairId('aaaaaa', 'bbbbbb'), 'aaaaaa_bbbbbb');
  assert.equal(pairId('aaaaaa', 'aaaaaa'), '');
  assert.equal(pairId('bad_id', 'aaaaaa'), '');
  const account = 'EPLsSBi4AbfuBcn20NIP6Y2T3bF3';
  const sample = 'sample-house-maid';
  assert.equal(pairId(sample, account), `${account}_${sample}`);
  assert.deepEqual(pairMembers(`${account}_${sample}`, account), [account, sample]);
});

test('only a member can name the pair', () => {
  assert.deepEqual(pairMembers('aaaaaa_bbbbbb', 'bbbbbb'), ['aaaaaa', 'bbbbbb']);
  assert.equal(pairMembers('aaaaaa_bbbbbb', 'cccccc'), null);
  assert.equal(pairMembers('aaaaaa_bbbbbb_cccccc', 'aaaaaa'), null);
});

test('text is trimmed and capped', () => {
  assert.equal(cleanText('  hi  '), 'hi');
  assert.equal(cleanText('   '), '');
  assert.equal(cleanText('x'.repeat(501)), '');
});

test('a stored meet link is not returned', () => {
  const row = viewMessage({ id: '1', from: 'a', at: 1, kind: 'video', meetUrl: 'https://meet.google.com/abc-defg-hij', expiresAt: 50 }, 40, '');
  assert.equal(row.meetUrl, undefined);
  assert.equal(row.kind, 'video');
});
