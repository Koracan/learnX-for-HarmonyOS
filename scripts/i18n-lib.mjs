// i18n-lib.mjs -- shared parser/naming helpers for the learnOH i18n tooling.
// The reference dictionaries are INPUT ONLY; nothing here writes to reference/.
import fs from 'node:fs';
import nodePath from 'node:path';

const SQ = String.fromCharCode(39);
const DQ = String.fromCharCode(34);
const BS = String.fromCharCode(92);
const OPEN_BRACE = String.fromCharCode(123);
const CLOSE_BRACE = String.fromCharCode(125);
const BACKTICK = String.fromCharCode(96);

// Template literals appear in the reference dictionaries (multi-line issue
// template text). Treat them as raw strings with backslash escapes.
function isQuote(c) { return c === SQ || c === DQ || c === BACKTICK; }
function isWs(c) { return c === ' ' || c === '\t' || c === '\n' || c === '\r'; }
function isKeyChar(c) { return /[A-Za-z0-9_$]/.test(c); }

// Tokenizer for the flat object literal used by the reference TS dictionaries.
// Handles single/double quotes, escapes, comments, and TS adjacent-literal
// string concatenation across newlines.
export function parseDict(source) {
  let i = 0;
  const n = source.length;
  const entries = [];
  const skipWs = () => { while (i < n && isWs(source[i])) i++; };
  const readString = () => {
    const quote = source[i];
    if (!isQuote(quote)) throw new Error('expected string at ' + i);
    let out = '';
    let closed = false;
    i++;
    while (i < n) {
      const c = source[i];
      if (c === BS) {
        const nxt = source[i + 1];
        if (nxt === 'n') out += '\n';
        else if (nxt === 't') out += '\t';
        else if (nxt === 'r') out += '\r';
        else out += nxt;
        i += 2;
        continue;
      }
      if (c === quote) { i++; closed = true; break; }
      out += c;
      i++;
    }
    if (!closed) throw new Error('unterminated string literal');
    return out;
  };
  while (i < n && source[i] !== OPEN_BRACE) i++;
  i++;
  for (;;) {
    skipWs();
    while (i < n && source[i] === '/' && (source[i + 1] === '/' || source[i + 1] === '*')) {
      if (source[i + 1] === '/') { while (i < n && source[i] !== '\n') i++; }
      else { i += 2; while (i < n && !(source[i] === '*' && source[i + 1] === '/')) i++; i += 2; }
      skipWs();
    }
    if (i >= n) throw new Error('unexpected EOF while parsing dictionary');
    if (source[i] === CLOSE_BRACE) break;
    let key;
    if (isQuote(source[i])) key = readString();
    else {
      let s = '';
      while (i < n && isKeyChar(source[i])) s += source[i++];
      key = s;
    }
    skipWs();
    if (source[i] !== ':') throw new Error('expected colon after key ' + key);
    i++;
    const parts = [];
    for (;;) {
      skipWs();
      if (!isQuote(source[i])) throw new Error('expected string value for key ' + key);
      parts.push(readString());
      skipWs();
      if (isQuote(source[i])) continue;
      break;
    }
    entries.push([key, parts.join('')]);
    skipWs();
    if (source[i] === ',') i++;
  }
  return entries;
}

export function readDict(file) {
  return parseDict(fs.readFileSync(file, 'utf8'));
}

// Reference key (camelCase identifier) -> HarmonyOS resource name.
// 'loh_' prefix guarantees no collision with template/other element names.
export function toResourceName(key) {
  return 'loh_' + key.replace(/([a-z0-9])([A-Z])/g, '$1_$2').toLowerCase();
}

const BRACE_RE = new RegExp(OPEN_BRACE + '(\\d+)' + CLOSE_BRACE, 'g');
const PRINTF_RE = new RegExp('%(\\d+\\$)?[sdf]', 'g');

// Placeholders: positional {N} tokens and already-valid printf forms.
export function findPlaceholders(value) {
  const found = [];
  let m;
  BRACE_RE.lastIndex = 0;
  while ((m = BRACE_RE.exec(value))) found.push({ token: m[0], index: Number(m[1]), style: 'brace' });
  PRINTF_RE.lastIndex = 0;
  while ((m = PRINTF_RE.exec(value))) found.push({ token: m[0], index: null, style: 'printf' });
  return found;
}

// {N} -> HarmonyOS positional placeholder %(N+1)$s ; printf forms untouched.
export function toResourceValue(value, placeholders) {
  let out = value;
  for (const ph of placeholders) {
    if (ph.style !== 'brace') continue;
    out = out.split(ph.token).join('%' + (ph.index + 1) + '$s');
  }
  return out;
}

// Reference keys the native rewrite deliberately does NOT migrate.
//
// The reference dictionaries are read-only INPUT, so a key that has no consumer in
// this app is retired here instead of inside reference/. Both the resource
// generator and check-i18n-keys.mjs go through buildRows, so this list is the
// single source of truth for "the reference dictionary as far as this project is
// concerned" -- retire a key and the generated resources, the manifest and the
// drift check all agree.
//
// 'avoidFrontCamera' / 'avoidFrontCameraDescription': the second switch on the
// immersive settings page. Its only platform effect in the reference app is the RN
// safe-area fallback (App.tsx:727, disableHeaderTopInsetFallback); this rewrite has
// no such fallback, so the switch was persisted and displayed but changed no layout.
// The switch is gone, and so are its copy keys.
export const RETIRED_REFERENCE_KEYS = [
  'avoidFrontCamera',
  'avoidFrontCameraDescription'
];

const RETIRED_REFERENCE_KEY_SET = new Set(RETIRED_REFERENCE_KEYS);

/** True when a reference key is deliberately not migrated. */
export function isRetiredReferenceKey(key) {
  return RETIRED_REFERENCE_KEY_SET.has(key);
}

// Cross-check the two reference dictionaries and build the row model.
// Retired keys (see RETIRED_REFERENCE_KEYS) are dropped; zhCount/enCount stay the
// raw dictionary sizes.
export function buildRows(refDir) {
  const zh = readDict(nodePath.join(refDir, 'zh.ts'));
  const en = readDict(nodePath.join(refDir, 'en.ts'));
  const zhKeys = zh.map((r) => r[0]);
  const enKeys = en.map((r) => r[0]);
  if (zhKeys.length !== enKeys.length) {
    throw new Error('zh/en key count mismatch: ' + zhKeys.length + ' vs ' + enKeys.length);
  }
  for (let k = 0; k < zhKeys.length; k++) {
    if (zhKeys[k] !== enKeys[k]) throw new Error('zh/en key order mismatch at ' + k);
  }
  const seen = new Map();
  const rows = [];
  for (let k = 0; k < zh.length; k++) {
    const key = zh[k][0];
    if (isRetiredReferenceKey(key)) continue;
    const name = toResourceName(key);
    if (seen.has(name)) throw new Error('resource name collision: ' + name);
    seen.set(name, key);
    const zhPh = findPlaceholders(zh[k][1]);
    const enPh = findPlaceholders(en[k][1]);
    rows.push({
      key: key,
      name: name,
      zhValue: toResourceValue(zh[k][1], zhPh),
      enValue: toResourceValue(en[k][1], enPh),
      zhPlaceholders: zhPh.map((p) => p.token),
      enPlaceholders: enPh.map((p) => p.token)
    });
  }
  return { rows: rows, zhCount: zh.length, enCount: en.length, retiredCount: RETIRED_REFERENCE_KEYS.length };
}

// Every reference dictionary value, keyed by its reference key.
export function dictMap(entries) {
  const m = new Map();
  for (const [k, v] of entries) m.set(k, v);
  return m;
}
