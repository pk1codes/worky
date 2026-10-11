function label(names, lang) {
  if (names && names[lang]) return names[lang];
  if (names && names.en) return names.en;
  return '';
}

function categoryTrail(byId, id, lang) {
  const names = [];
  const seen = new Set();
  let cur = id || '';
  while (cur && !seen.has(cur)) {
    seen.add(cur);
    const row = byId.get(cur);
    if (!row) break;
    const name = label(row.names, lang);
    if (name) names.push(name);
    cur = row.parentId || '';
  }
  names.reverse();
  return names;
}

module.exports = { categoryTrail };
