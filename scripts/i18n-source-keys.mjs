// i18n-source-keys.mjs
//
// Cross-checks every resource key referenced from ArkTS source against the
// resource manifest. Catches the bug class where a component references
// `$r('app.string.ui_foo')` but the generated resource is named differently
// (or the key was renamed) -- otherwise only visible as a blank label on device.
//
// Also verifies placeholder arity for typed `t()` calls: the manifest records
// how many placeholders each resource value carries.
import fs from 'node:fs';
import path from 'node:path';

const SQ = String.fromCharCode(39);
const DQ = String.fromCharCode(34);
const BSLASH = String.fromCharCode(92);

// Removes block and line comments so doc examples such as
// $r('app.string.xxx') are not mistaken for real references.
function stripComments(source) {
  let out = '';
  let i = 0;
  const n = source.length;
  let quote = '';
  while (i < n) {
    const ch = source[i];
    const next = i + 1 < n ? source[i + 1] : '';
    if (quote.length > 0) {
      out += ch;
      if (ch === BSLASH) { if (i + 1 < n) { out += source[i + 1]; i += 2; continue; } }
      else if (ch === quote) { quote = ''; }
      i++;
      continue;
    }
    if (ch === SQ || ch === DQ) { quote = ch; out += ch; i++; continue; }
    if (ch === '/' && next === '/') { while (i < n && source[i] !== String.fromCharCode(10)) i++; continue; }
    if (ch === '/' && next === '*') { i += 2; while (i < n && !(source[i] === '*' && source[i + 1] === '/')) i++; i += 2; continue; }
    out += ch;
    i++;
  }
  return out;
}

function walk(dir, out) {
  if (!fs.existsSync(dir)) return out;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(full, out);
    else if (entry.name.endsWith('.ets')) out.push(full);
  }
  return out;
}

// Splits a call-argument list on top-level commas.
function splitArgs(body) {
  const out = [];
  let depth = 0;
  let quote = '';
  let cur = '';
  for (let i = 0; i < body.length; i++) {
    const ch = body[i];
    if (quote.length > 0) {
      cur += ch;
      if (ch === quote) quote = '';
      continue;
    }
    if (ch === SQ || ch === DQ) { quote = ch; cur += ch; continue; }
    if (ch === '(' || ch === '{' || ch === '[') depth++;
    if (ch === ')' || ch === '}' || ch === ']') depth--;
    if (ch === ',' && depth === 0) { out.push(cur.trim()); cur = ''; continue; }
    cur += ch;
  }
  if (cur.trim().length > 0) out.push(cur.trim());
  return out;
}

// Returns the top-level argument list of the call whose '(' is at or after start.
function callArgs(source, start) {
  let i = source.indexOf('(', start);
  if (i < 0) return null;
  const begin = i + 1;
  let depth = 0;
  let quote = '';
  for (; i < source.length; i++) {
    const ch = source[i];
    if (quote.length > 0) {
      if (ch === quote && source[i - 1] !== BSLASH) quote = '';
      continue;
    }
    if (ch === SQ || ch === DQ) { quote = ch; continue; }
    if (ch === '(') depth++;
    if (ch === ')') {
      depth--;
      if (depth === 0) return splitArgs(source.slice(begin, i));
    }
  }
  return null;
}

const APP_STRING_RE = new RegExp("[$]r[(]'app[.]string[.]([A-Za-z0-9_]+)'", 'g');
const T_RE = new RegExp("[^A-Za-z0-9_]t[(]'(loh_[A-Za-z0-9_]+|ui_[A-Za-z0-9_]+)'", 'g');
const T_NAME_RE = new RegExp("[^A-Za-z0-9_]tName[(]'([A-Za-z0-9_]+)'", 'g');

export function checkSourceKeys(root, manifest) {
  const known = new Set(manifest.keys.map((k) => k.name));
  const placeholders = new Map();
  for (const k of manifest.keys) {
    placeholders.set(k.name, (k.zhPlaceholders || []).length);
  }
  const files = walk(path.join(root, 'entry', 'src', 'main', 'ets'), [])
    .concat(walk(path.join(root, 'entry', 'src', 'test'), []));
  const problems = [];
  const used = new Set();
  const patterns = [
    { re: APP_STRING_RE, kind: 'app.string' },
    { re: T_RE, kind: 't()' },
    { re: T_NAME_RE, kind: 'tName()' }
  ];
  for (const file of files) {
    const source = stripComments(fs.readFileSync(file, 'utf8'));
    const rel = path.relative(root, file);
    for (const p of patterns) {
      p.re.lastIndex = 0;
      let m = p.re.exec(source);
      while (m !== null) {
        const name = m[1];
        used.add(name);
        if (!known.has(name)) {
          problems.push({ file: rel, kind: p.kind, name: name, reason: 'not present in the resource manifest' });
        } else if (p.kind === 't()') {
          const args = callArgs(source, m.index);
          const expected = placeholders.get(name) || 0;
          if (args !== null) {
            if (args.length - 1 > expected) {
              problems.push({ file: rel, kind: 't()', name: name, reason: 'more arguments than placeholders (' + String(args.length - 1) + ' > ' + String(expected) + ')' });
            }
            if (args.length - 1 < expected) {
              problems.push({ file: rel, kind: 't()', name: name, reason: 'fewer arguments than placeholders (' + String(args.length - 1) + ' < ' + String(expected) + ')' });
            }
          }
        }
        m = p.re.exec(source);
      }
    }
  }
  return { problems: problems, usedCount: used.size, used: [...used].sort() };
}
