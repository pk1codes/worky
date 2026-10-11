const test = require('node:test');
const assert = require('node:assert/strict');
const { categoryTrail } = require('../lib/categories');

const tree = new Map([
  ['cook', { parentId: '', names: { en: 'Cook' } }],
  ['oil-field-rigs', { parentId: '', names: { en: 'Oil Field Rigs' } }],
  ['driller', { parentId: 'oil-field-rigs', names: { en: 'Driller' } }],
  ['oil-company-jobs', { parentId: 'oil-field-rigs', names: { en: 'Oil Company Jobs' } }],
  ['kb-drilling-engineer', { parentId: 'oil-company-jobs', names: { en: 'Drilling Engineer' } }],
  ['loop-a', { parentId: 'loop-b', names: { en: 'A' } }],
  ['loop-b', { parentId: 'loop-a', names: { en: 'B' } }],
]);

test('a root job is only its own name', () => {
  assert.deepEqual(categoryTrail(tree, 'cook', 'en'), ['Cook']);
});

test('a nested job includes each parent', () => {
  assert.deepEqual(categoryTrail(tree, 'driller', 'en'), ['Oil Field Rigs', 'Driller']);
});

test('a deeper job keeps every level', () => {
  assert.deepEqual(categoryTrail(tree, 'kb-drilling-engineer', 'en'), [
    'Oil Field Rigs',
    'Oil Company Jobs',
    'Drilling Engineer',
  ]);
});

test('a missing category is an empty path', () => {
  assert.deepEqual(categoryTrail(tree, 'gone', 'en'), []);
  assert.deepEqual(categoryTrail(tree, '', 'en'), []);
});

test('a parent cycle stops', () => {
  assert.deepEqual(categoryTrail(tree, 'loop-a', 'en'), ['B', 'A']);
});
