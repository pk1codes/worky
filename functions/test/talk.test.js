const test = require('node:test');
const assert = require('node:assert');
const { pairId, pairMembers, cleanText, googleMatch, meetBody, meetUrl, viewMessage } = require('../lib/talk');

test('a pair id is the two accounts sorted once', () => {
  assert.equal(pairId('bbbbbb', 'aaaaaa'), 'aaaaaa_bbbbbb');
  assert.equal(pairId('aaaaaa', 'bbbbbb'), 'aaaaaa_bbbbbb');
  assert.equal(pairId('aaaaaa', 'aaaaaa'), '');
  assert.equal(pairId('bad_id', 'aaaaaa'), '');
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

test('the calendar host must be the same Google account', () => {
  const providers = [{ providerId: 'google.com', uid: 'google-sub' }];
  assert.equal(googleMatch('google-sub', providers), true);
  assert.equal(googleMatch('firebase-uid', providers), false);
  assert.equal(googleMatch('google-sub', [{ providerId: 'password', uid: 'google-sub' }]), false);
});

test('a meet event asks Calendar to create a conference', () => {
  const body = meetBody(1_700_000_000_000, 'req-1');
  assert.equal(body.conferenceData.createRequest.requestId, 'req-1');
  assert.equal(body.conferenceData.createRequest.conferenceSolutionKey.type, 'hangoutsMeet');
  assert.equal(body.summary, 'Worky Talk');
  assert.ok(!body.attendees);
});

test('only a meet link is kept', () => {
  assert.equal(
    meetUrl({ conferenceData: { entryPoints: [{ entryPointType: 'video', uri: 'https://meet.google.com/abc-defg-hij?x=1' }] } }),
    'https://meet.google.com/abc-defg-hij',
  );
  assert.equal(meetUrl({ hangoutLink: 'https://example.com/nope' }), '');
});

test('a video link is hidden after it expires', () => {
  const live = viewMessage({ id: '1', from: 'a', at: 1, kind: 'video', meetUrl: 'https://meet.google.com/abc-defg-hij', expiresAt: 50 }, 40, '');
  const dead = viewMessage({ id: '1', from: 'a', at: 1, kind: 'video', meetUrl: 'https://meet.google.com/abc-defg-hij', expiresAt: 50 }, 60, '');
  assert.equal(live.meetUrl, 'https://meet.google.com/abc-defg-hij');
  assert.equal(dead.meetUrl, undefined);
});
