// Extract CONFIG, computeSiteTagsToAdd, itemHasAuthorshipCreator from the patched
// file and run them against real cases. Stub the Zotero item API surface each uses:
// getField('url'|'libraryCatalog'), hasTag(name), numCreators(), getCreatorJSON(i).
// Zotero.CreatorTypes is NOT stubbed on purpose -- this build returns creatorType
// as a lowercase string (verified via resolve_items), so branch 1 is the live path
// and the id-resolution branch must not be needed.

const fs = require('fs');
let src = fs.readFileSync('normalize_items.js', 'utf8');

// Pull the CONFIG object literal (var CONFIG = { ... };) and the two functions by
// slicing between known anchors, then eval in a controlled scope.
function slice(from, toAnchor, name) {
  const start = src.indexOf(from);
  if (start === -1) throw new Error('anchor not found: ' + name + ' :: ' + from);
  const end = src.indexOf(toAnchor, start);
  if (end === -1) throw new Error('end anchor not found: ' + name);
  return src.slice(start, end);
}

const configText = slice('var CONFIG = {', '\n// 2. STATE', 'CONFIG');
const computeText = slice('function computeSiteTagsToAdd', '\n// R4 helper', 'compute');
const authText = slice('function itemHasAuthorshipCreator', '\nvar RULES', 'auth');

// Zotero global: only CreatorTypes is referenced, inside the guarded id branch.
// Leave it undefined to prove the string branch handles every real case.
const Zotero = {};

eval(configText);
eval(authText);
eval(computeText);

// Stub item factory. creators: array of {type, last} ; tags: array of strings.
function makeItem(fields, creators, tags) {
  return {
    getField: (f) => fields[f] || '',
    hasTag: (t) => tags.indexOf(t) !== -1,
    numCreators: () => creators.length,
    getCreatorJSON: (i) => {
      const c = creators[i];
      return { creatorType: c.type, lastName: c.last, firstName: c.first || '' };
    }
  };
}

const cases = [
  // [label, fields, creators, tags, expectedToAdd]
  ['authored GBooks book (reported FP)',
    {libraryCatalog:'Google Books'}, [{type:'author',last:'Kernighan'}], [],
    ['__add-file']],  // metadata suppressed (has author), file still flagged (R3 scope)
  ['authorless GBooks item',
    {libraryCatalog:'Google Books'}, [], [],
    ['__add-metadata','__add-file']],  // both flagged: genuinely incomplete
  ['authored GBooks book + __print',
    {libraryCatalog:'Google Books'}, [{type:'author',last:'Knuth'}], ['__print'],
    []],  // metadata suppressed (author), file suppressed (__print) -> nothing
  ['authorless GBooks + __print',
    {libraryCatalog:'Google Books'}, [], ['__print'],
    ['__add-metadata']],  // file suppressed by print, metadata still needed
  ['GBooks video director-only',
    {libraryCatalog:'Google Books'}, [{type:'director',last:'OaklandLYM'}], [],
    ['__add-metadata','__add-file']],  // director excluded -> still incomplete
  ['GBooks video creator-credited',
    {libraryCatalog:'Google Books'}, [{type:'creator',last:'Corbett'}], [],
    ['__add-file']],  // creator now counts -> metadata suppressed
  ['GBooks programmer item',
    {libraryCatalog:'Google Books'}, [{type:'programmer',last:'Eddelbuettel'}], [],
    ['__add-file']],
  ['GBooks artwork',
    {libraryCatalog:'Google Books'}, [{type:'artist',last:'Sesina'}], [],
    ['__add-file']],
  ['non-GBooks authored book (no match)',
    {libraryCatalog:'Library of Congress'}, [{type:'author',last:'Numbers'}], [],
    []],  // site does not match -> R2 adds nothing regardless
  ['GBooks by url not catalog',
    {url:'https://books.google.com/books?id=abc'}, [{type:'author',last:'x'}], [],
    ['__add-file']],  // url match path, metadata suppressed by author
  ['already fully tagged authored GBooks',
    {libraryCatalog:'Google Books'}, [{type:'author',last:'x'}], ['__add-file'],
    []],  // author suppresses metadata, file already present -> nothing
];

// authorship predicate direct checks
const authChecks = [
  ['author -> true', [{type:'author',last:'x'}], true],
  ['editor -> true', [{type:'editor',last:'x'}], true],
  ['creator -> true', [{type:'creator',last:'x'}], true],
  ['programmer -> true', [{type:'programmer',last:'x'}], true],
  ['artist -> true', [{type:'artist',last:'x'}], true],
  ['director -> false', [{type:'director',last:'x'}], false],
  ['translator -> false', [{type:'translator',last:'x'}], false],
  ['none -> false', [], false],
  ['director + author -> true', [{type:'director',last:'x'},{type:'author',last:'y'}], true],
  ['uppercase Author still true (defensive)', [{type:'Author',last:'x'}], true],
];

let pass = 0, fail = 0;
console.log('=== itemHasAuthorshipCreator ===');
for (const [label, creators, expected] of authChecks) {
  const got = itemHasAuthorshipCreator(makeItem({}, creators, []));
  const ok = got === expected;
  console.log(`${ok?'PASS':'FAIL'}  ${label}  (got ${got})`);
  ok ? pass++ : fail++;
}

console.log('\n=== computeSiteTagsToAdd ===');
for (const [label, fields, creators, tags, expected] of cases) {
  const got = computeSiteTagsToAdd(makeItem(fields, creators, tags));
  const ok = JSON.stringify(got.slice().sort()) === JSON.stringify(expected.slice().sort());
  console.log(`${ok?'PASS':'FAIL'}  ${label}\n        expected [${expected}]  got [${got}]`);
  ok ? pass++ : fail++;
}

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail === 0 ? 0 : 1);
