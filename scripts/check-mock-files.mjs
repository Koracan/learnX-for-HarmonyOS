#!/usr/bin/env node
/*
 * Mock 样例文件的**结构校验器**（scripts）。
 *
 * 与 scripts/gen-mock-files.mjs 成对：生成器负责产出，本脚本负责在提交前 FAIL 掉
 * "看起来像个文件、其实打不开"的产物。校验的是**结构**，不是"与重新生成的结果逐字节相同"
 * —— 后者会让换机器 / 换 zlib 版本变成假红。
 *
 * ## PDF 校验什么
 *
 *   1. 头是 %PDF-1.x，尾是 %%EOF；
 *   2. startxref 指向的偏移处**真的**是 xref 关键字；
 *   3. xref 表里每个 n 条目的偏移**真的**指向 "<n> 0 obj"；
 *   4. /Type /Page 的页对象至少 1 个，且 Pages 的 /Count 与实际页数一致；
 *   5. 每一页都能找到内容流，流的字节数等于 /Length，且正文里有 Tj（= 页面上真有文字）。
 *
 * ## PPTX 校验什么
 *
 *   1. ZIP 本地头逐个可解析（签名 / STORE / 长度 / CRC32 逐字节重算）；
 *   2. **[Content_Types].xml 是第一个成员**（OOXML 的硬要求）；
 *   3. 十一个必需部件齐全（presentation / slideMaster / slideLayout / slide / theme
 *      以及各自的 rels 与根 _rels/.rels）；
 *   4. 每个部件都是**良构 XML**（手写标签配平扫描）；
 *   5. 每个 .rels 的每个内部 Target 都能解析到**存在的部件**（关系不断链）；
 *   6. 中央目录 + EOCD 的成员数与本地头一致。
 *
 * ## PNG 校验什么
 *
 *   1. 8 字节签名；
 *   2. 逐个 chunk 的长度/边界**自洽**，且每个 chunk 的 CRC32（类型+数据）与存储值一致；
 *   3. IHDR 是第一个 chunk、长度 13、宽高非零、8bit 真彩（colorType 2）、无隔行；
 *   4. IDAT 拼起来能被 zlib 解压，解压后的长度恰好 = height × (1 + width×3)，
 *      且每行的 filter 字节是 0..4（越界 = 结构坏了）；
 *   5. IEND 存在。
 * **负向可验**：改一个字节（哪怕只改像素）⇒ 那个 chunk 的 CRC 对不上 ⇒ FAIL。
 * 图片预览在设备上走系统 image.createImageSource，所以这份样例是**没有 HMS 的设备上**
 * 唯一能演示"应用内真的渲染出来了"的那一份（PDF 预览依赖 HMS 的 pdfservice）。
 *
 * **诚实边界**：这些校验**不能**证明"PowerPoint/WPS 一定能打开"或"PDFKit 一定
 * PARSE_SUCCESS"——那需要真机/真应用。真机预览由统筹者验收；本脚本拦的是结构错误。
 *
 * ## 用法
 *
 *   node scripts/check-mock-files.mjs
 * 退出码：0 = 全 PASS；1 = 有 FAIL；2 = 一个文件都没有（防空跑误判为通过）。
 */

import { existsSync, readFileSync, statSync } from 'node:fs';
import { dirname, join, posix, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { inflateSync } from 'node:zlib';

const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const FILE_DIR = join(REPO_ROOT, 'entry', 'src', 'main', 'resources', 'rawfile', 'mock-files');
const BLOBS_SOURCE = join(REPO_ROOT, 'entry', 'src', 'main', 'ets', 'data', 'mock',
  'MockFileBlobs.ets');

const PDF_CONTENT_TYPE = 'application/pdf';
const PPTX_CONTENT_TYPE =
  'application/vnd.openxmlformats-officedocument.presentationml.presentation';
const PNG_CONTENT_TYPE = 'image/png';

/**
 * 必须存在的六个产物。
 *
 * 101..104 与 106 是 MockData.mockFiles() 的五条样例（106 是那张 PNG）；
 * 105 是 mockNotices() 那条附件的样例。
 */
const EXPECTED = [
  { fileName: 'mock-course-syllabus.pdf', kind: 'pdf', contentType: PDF_CONTENT_TYPE },
  { fileName: 'mock-homework-1-answers.pdf', kind: 'pdf', contentType: PDF_CONTENT_TYPE },
  { fileName: 'mock-physics-lab-manual.pdf', kind: 'pdf', contentType: PDF_CONTENT_TYPE },
  { fileName: 'mock-lecture-notes-3.pptx', kind: 'pptx', contentType: PPTX_CONTENT_TYPE },
  { fileName: 'mock-notice-attachment.pdf', kind: 'pdf', contentType: PDF_CONTENT_TYPE },
  { fileName: 'mock-lab-schedule.png', kind: 'png', contentType: PNG_CONTENT_TYPE }
];

const REQUIRED_PPTX_PARTS = [
  '[Content_Types].xml',
  '_rels/.rels',
  'ppt/presentation.xml',
  'ppt/_rels/presentation.xml.rels',
  'ppt/slides/slide1.xml',
  'ppt/slides/_rels/slide1.xml.rels',
  'ppt/slideLayouts/slideLayout1.xml',
  'ppt/slideLayouts/_rels/slideLayout1.xml.rels',
  'ppt/slideMasters/slideMaster1.xml',
  'ppt/slideMasters/_rels/slideMaster1.xml.rels',
  'ppt/theme/theme1.xml'
];

const failures = [];

function pass(label, detail) {
  console.log('[check-mock-files] PASS ' + label + (detail === undefined ? '' : ': ' + detail));
}

function fail(label, detail) {
  failures.push(label + ': ' + detail);
  console.log('[check-mock-files] FAIL ' + label + ': ' + detail);
}

function expect(label, condition, detail) {
  if (condition) {
    return true;
  }
  fail(label, detail);
  return false;
}

/* ------------------------------------------------------------------ *
 * XML：良构性（标签配平）+ 属性抽取
 * ------------------------------------------------------------------ */

/** 返回 '' = 良构；否则是问题描述。手写扫描，无第三方依赖。 */
function xmlProblem(text) {
  // XML 声明与处理指令不是元素，先摘掉，否则末尾的 "<" 残留检查会误报。
  const stripped = text.replace(/<\?[\s\S]*?\?>/g, '').replace(/<!--[\s\S]*?-->/g, '');
  const tag = /<(\/?)([A-Za-z_][\w.:-]*)((?:"[^"]*"|'[^']*'|[^>"'])*?)(\/?)>/g;
  const stack = [];
  let count = 0;
  let match = tag.exec(stripped);
  while (match !== null) {
    count++;
    const closing = match[1] === '/';
    const name = match[2];
    const selfClosing = match[4] === '/';
    if (closing) {
      if (stack.length === 0 || stack[stack.length - 1] !== name) {
        return 'unbalanced closing tag </' + name + '>';
      }
      stack.pop();
    } else if (!selfClosing) {
      stack.push(name);
    }
    match = tag.exec(stripped);
  }
  if (count === 0) {
    return 'no XML elements found';
  }
  if (stack.length > 0) {
    return 'unclosed tag <' + stack[stack.length - 1] + '>';
  }
  const leftover = stripped.replace(tag, '');
  if (leftover.indexOf('<') >= 0) {
    return 'stray "<" outside any tag';
  }
  return '';
}

/** 抽取所有 <Relationship .../> 的 Id / Type / Target / TargetMode。 */
function relationships(text) {
  const out = [];
  const re = /<Relationship\b([^>]*)\/?>/g;
  let match = re.exec(text);
  while (match !== null) {
    const attrs = match[1];
    const read = (name) => {
      const m = new RegExp(name + '="([^"]*)"').exec(attrs);
      return m === null ? '' : m[1];
    };
    out.push({ id: read('Id'), type: read('Type'), target: read('Target'),
      mode: read('TargetMode') });
    match = re.exec(text);
  }
  return out;
}

/* ------------------------------------------------------------------ *
 * ZIP（STORE）：本地头 → 部件 → EOCD → 中央目录
 * ------------------------------------------------------------------ */

const CRC_TABLE = (() => {
  const table = new Int32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) {
      c = (c & 1) ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);
    }
    table[n] = c;
  }
  return table;
})();

function crc32(buf) {
  let c = 0xFFFFFFFF;
  for (let i = 0; i < buf.length; i++) {
    c = CRC_TABLE[(c ^ buf[i]) & 0xFF] ^ (c >>> 8);
  }
  return (c ^ 0xFFFFFFFF) >>> 0;
}

/** 解析本地头序列，返回 { parts: [{name,data}], problems: [] }。 */
function readZip(buf) {
  const problems = [];
  const parts = [];
  let offset = 0;
  for (;;) {
    if (offset + 30 > buf.length) {
      break;
    }
    if (buf.readUInt32LE(offset) !== 0x04034b50) {
      break;
    }
    const flags = buf.readUInt16LE(offset + 6);
    const method = buf.readUInt16LE(offset + 8);
    const crc = buf.readUInt32LE(offset + 14);
    const size = buf.readUInt32LE(offset + 18);
    const nameLength = buf.readUInt16LE(offset + 26);
    const extraLength = buf.readUInt16LE(offset + 28);
    const nameStart = offset + 30;
    const dataStart = nameStart + nameLength + extraLength;
    const name = buf.toString('utf8', nameStart, nameStart + nameLength);
    if ((flags & 0x0008) !== 0) {
      problems.push(name + ': uses a data descriptor (unsupported by this checker)');
    }
    if (method !== 0) {
      problems.push(name + ': compression method is ' + method + ', expected 0 (stored)');
    }
    if (dataStart + size > buf.length) {
      problems.push(name + ': data runs past the end of the archive');
      break;
    }
    const data = buf.subarray(dataStart, dataStart + size);
    if (crc32(data) !== crc) {
      problems.push(name + ': CRC32 mismatch (stored ' + crc + ', computed ' + crc32(data) + ')');
    }
    parts.push({ name: name, data: data });
    offset = dataStart + size;
  }
  // EOCD 在最后 22 字节（无注释）。
  const eocdAt = buf.length - 22;
  if (eocdAt < 0 || buf.readUInt32LE(eocdAt) !== 0x06054b50) {
    problems.push('EOCD (end of central directory) not found in the last 22 bytes');
    return { parts: parts, problems: problems };
  }
  const entries = buf.readUInt16LE(eocdAt + 10);
  const centralSize = buf.readUInt32LE(eocdAt + 12);
  const centralOffset = buf.readUInt32LE(eocdAt + 16);
  if (entries !== parts.length) {
    problems.push('EOCD says ' + entries + ' members, local headers say ' + parts.length);
  }
  if (centralOffset + centralSize !== eocdAt) {
    problems.push('central directory does not end where the EOCD starts');
  }
  if (buf.readUInt32LE(centralOffset) !== 0x02014b50) {
    problems.push('no central directory entry at offset ' + centralOffset);
  }
  return { parts: parts, problems: problems };
}

/* ------------------------------------------------------------------ *
 * PDF
 * ------------------------------------------------------------------ */

/** 返回一行结论描述；问题直接进 fail()。 */
function checkPdf(fileName, buf) {
  const text = buf.toString('latin1');
  let ok = true;
  ok = expect(fileName, /^%PDF-1\.[0-9]\r?\n/.test(text), 'missing a %PDF-1.x header') && ok;
  ok = expect(fileName, text.trimEnd().endsWith('%%EOF'), 'does not end with %%EOF') && ok;

  const marker = /startxref\s+(\d+)\s+%%EOF\s*$/.exec(text);
  if (!expect(fileName, marker !== null, 'no "startxref <offset> %%EOF" trailer')) {
    return null;
  }
  const xrefOffset = Number(marker[1]);
  ok = expect(fileName, text.startsWith('xref', xrefOffset),
    'startxref points at ' + xrefOffset + ', where the text is "'
    + text.substring(xrefOffset, xrefOffset + 8) + '"') && ok;

  const header = /^xref\r?\n0 (\d+)\r?\n/.exec(text.substring(xrefOffset));
  if (!expect(fileName, header !== null, 'no xref subsection header "0 <count>"')) {
    return null;
  }
  const entryCount = Number(header[1]);
  const tableStart = xrefOffset + header[0].length;
  let resolved = 0;
  for (let n = 1; n < entryCount; n++) {
    const entry = text.substr(tableStart + n * 20, 20);
    if (entry.length !== 20) {
      fail(fileName, 'xref entry ' + n + ' is truncated');
      ok = false;
      break;
    }
    if (entry.charAt(17) !== 'n') {
      fail(fileName, 'xref entry ' + n + ' is not an in-use object: "' + entry + '"');
      ok = false;
      break;
    }
    const objectOffset = Number(entry.substring(0, 10));
    if (!text.startsWith(n + ' 0 obj', objectOffset)) {
      fail(fileName, 'xref entry ' + n + ' points at ' + objectOffset + ', where the text is "'
        + text.substring(objectOffset, objectOffset + 16).replace(/\n/g, '\\n') + '"');
      ok = false;
      break;
    }
    resolved++;
  }

  // 先扫对象头（数字 + 0 obj），再按结束标记切片。
  // 为什么不写成一个"头 + 非贪婪体 + 尾"的正则：那样尾部的换行会被**吃掉**，
  // 下一个匹配就找不到自己的前导换行，于是只解析出隔一个的对象（本脚本第一版
  // 实测就是这个症状：10 个对象只解析出 5 个）。
  const objects = new Map();
  const objectRe = /(?:^|\n)(\d+) 0 obj\n/g;
  let match = objectRe.exec(text);
  while (match !== null) {
    const start = match.index + match[0].length;
    const end = text.indexOf('\nendobj\n', start);
    if (end < 0) {
      fail(fileName, 'object ' + match[1] + ' has no trailing endobj');
      ok = false;
      break;
    }
    objects.set(Number(match[1]), text.substring(start, end));
    objectRe.lastIndex = end;
    match = objectRe.exec(text);
  }
  if (!expect(fileName, objects.size === entryCount - 1,
    'xref declares ' + (entryCount - 1) + ' objects but ' + objects.size + ' were parsed')) {
    ok = false;
  }
  if (!expect(fileName, objects.has(1) && objects.get(1).indexOf('/Type /Catalog') >= 0,
    'object 1 is not a /Catalog')) {
    ok = false;
  }
  const trailer = /trailer\s*<<([\s\S]*?)>>\s*startxref/.exec(text);
  ok = expect(fileName, trailer !== null && /\/Root\s+1\s+0\s+R/.test(trailer[1]),
    'trailer has no "/Root 1 0 R"') && ok;

  const pageNumbers = [];
  for (const [number, body] of objects) {
    if (/\/Type\s*\/Page\b/.test(body)) {
      pageNumbers.push(number);
    }
  }
  if (!expect(fileName, pageNumbers.length >= 1, 'no /Type /Page object found')) {
    return null;
  }
  const pagesBody = objects.get(2) === undefined ? '' : objects.get(2);
  ok = expect(fileName, new RegExp('/Count\\s+' + pageNumbers.length + '\\b').test(pagesBody),
    'the /Pages object does not declare /Count ' + pageNumbers.length) && ok;

  let textBytes = 0;
  for (const number of pageNumbers) {
    const body = objects.get(number);
    const contentRef = /\/Contents\s+(\d+)\s+0\s+R/.exec(body);
    if (!expect(fileName, contentRef !== null, 'page object ' + number + ' has no /Contents')) {
      ok = false;
      continue;
    }
    const contentNumber = Number(contentRef[1]);
    const contentBody = objects.get(contentNumber);
    if (!expect(fileName, contentBody !== undefined,
      'page ' + number + ' references missing content object ' + contentNumber)) {
      ok = false;
      continue;
    }
    const lengthMatch = /^<< \/Length (\d+) >>\nstream\n/.exec(contentBody);
    if (!expect(fileName, lengthMatch !== null,
      'content object ' + contentNumber + ' has no "/Length N >> stream"')) {
      ok = false;
      continue;
    }
    const declared = Number(lengthMatch[1]);
    const streamText = contentBody.substring(lengthMatch[0].length);
    if (!expect(fileName, streamText.substring(declared, declared + 9) === 'endstream',
      'content object ' + contentNumber + ' /Length ' + declared + ' does not land on endstream')) {
      ok = false;
      continue;
    }
    const stream = streamText.substring(0, declared);
    if (!expect(fileName, stream.indexOf(' Tj') > 0,
      'content object ' + contentNumber + ' draws no text (no Tj operator)')) {
      ok = false;
    }
    textBytes += declared;
  }
  if (!ok) {
    return null;
  }
  return 'header/xref/startxref/EOF ok, objects=' + objects.size + ', pages='
    + pageNumbers.length + ', textStreamBytes=' + textBytes;
}

/* ------------------------------------------------------------------ *
 * PPTX
 * ------------------------------------------------------------------ */

function checkPptx(fileName, buf) {
  const zip = readZip(buf);
  for (const problem of zip.problems) {
    fail(fileName, problem);
  }
  let ok = zip.problems.length === 0;
  const names = zip.parts.map((part) => part.name);
  const byName = new Map(zip.parts.map((part) => [part.name, part.data]));

  ok = expect(fileName, names.length > 0, 'the archive has no members at all') && ok;
  ok = expect(fileName, names[0] === '[Content_Types].xml',
    'the first member is "' + names[0] + '", not [Content_Types].xml') && ok;
  for (const required of REQUIRED_PPTX_PARTS) {
    ok = expect(fileName, byName.has(required), 'missing required part ' + required) && ok;
  }

  const problems = [];
  const contentTypes = byName.get('[Content_Types].xml');
  if (contentTypes !== undefined) {
    const parsed = xmlProblem(contentTypes.toString('utf8'));
    if (parsed.length > 0) {
      problems.push('[Content_Types].xml is not well-formed XML: ' + parsed);
    }
    const declared = contentTypes.toString('utf8');
    for (const name of names) {
      if (name === '[Content_Types].xml') {
        continue;
      }
      const extension = name.substring(name.lastIndexOf('.') + 1);
      const covered = declared.indexOf('PartName="/' + name + '"') >= 0
        || declared.indexOf('Extension="' + extension + '"') >= 0;
      if (!covered) {
        problems.push('no content type covers part ' + name);
      }
    }
  }

  for (const name of names) {
    if (!name.endsWith('.xml') && !name.endsWith('.rels')) {
      continue;
    }
    const text = byName.get(name).toString('utf8');
    const problem = xmlProblem(text);
    if (problem.length > 0) {
      problems.push(name + ' is not well-formed XML: ' + problem);
    }
    if (name.endsWith('.rels')) {
      // 关系源部件：X/_rels/<name>.rels → X/<name>（根 _rels/.rels → 包根）。
      const dir = name.substring(0, name.indexOf('_rels/'));
      for (const rel of relationships(text)) {
        if (rel.mode === 'External' || rel.target.length === 0) {
          continue;
        }
        // 一律按 **POSIX** 解析：ZIP 成员名永远是正斜杠，而 node:path 的默认
        // resolve 在 Windows 上会返回 "D:\\..." 反斜杠路径（实测），那样永远对不上。
        const target = posix.resolve('/', dir, rel.target).substring(1);
        if (!byName.has(target)) {
          problems.push(name + ' rId=' + rel.id + ' targets missing part ' + target);
        }
      }
    }
  }
  for (const problem of problems) {
    fail(fileName, problem);
  }
  ok = ok && problems.length === 0;
  if (!ok) {
    return null;
  }
  return 'zip members=' + names.length + ', [Content_Types].xml first, required parts ok, '
    + 'XML well-formed, all relationship targets resolve';
}

/* ------------------------------------------------------------------ *
 * PNG
 * ------------------------------------------------------------------ */

/** PNG 的 8 字节签名（与生成器逐字一致）。 */
const PNG_SIGNATURE = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];

/**
 * 逐 chunk 校验：签名 / 边界 / CRC / IHDR 自洽 / IDAT 可解压 / IEND 存在。
 *
 * 为什么连 CRC 都要重算：CRC 是"这份字节与它自称的内容一致"的唯一证据；
 * 只检查签名与 IHDR，改坏一个像素也发现不了（负向可验就靠 CRC）。
 */
function checkPng(fileName, buf) {
  const problems = [];
  if (buf.length < PNG_SIGNATURE.length) {
    fail(fileName, 'file is shorter than the PNG signature');
    return null;
  }
  for (let i = 0; i < PNG_SIGNATURE.length; i++) {
    if (buf[i] !== PNG_SIGNATURE[i]) {
      problems.push('signature byte ' + i + ' is ' + buf[i] + ', expected ' + PNG_SIGNATURE[i]);
    }
  }

  let offset = PNG_SIGNATURE.length;
  let ihdr = null;
  let sawIhdr = false;
  let sawIend = false;
  let chunks = 0;
  const idatParts = [];
  while (offset + 12 <= buf.length) {
    const length = buf.readUInt32BE(offset);
    const type = buf.toString('latin1', offset + 4, offset + 8);
    const dataStart = offset + 8;
    const dataEnd = dataStart + length;
    if (dataEnd + 4 > buf.length) {
      problems.push(type + ': chunk length ' + length + ' runs past the end of the file');
      break;
    }
    const storedCrc = buf.readUInt32BE(dataEnd);
    const computedCrc = crc32(buf.subarray(offset + 4, dataEnd));
    if (storedCrc !== computedCrc) {
      problems.push(type + ': CRC mismatch (stored=' + storedCrc
        + ', computed=' + computedCrc + ')');
    }
    if (type === 'IHDR') {
      if (sawIhdr) {
        problems.push('duplicate IHDR');
      }
      sawIhdr = true;
      if (length !== 13) {
        problems.push('IHDR length is ' + length + ', expected 13');
      } else {
        ihdr = {
          width: buf.readUInt32BE(dataStart),
          height: buf.readUInt32BE(dataStart + 4),
          bitDepth: buf[dataStart + 8],
          colorType: buf[dataStart + 9],
          compression: buf[dataStart + 10],
          filter: buf[dataStart + 11],
          interlace: buf[dataStart + 12]
        };
      }
    } else if (!sawIhdr) {
      problems.push('first chunk is ' + type + ', expected IHDR');
    }
    if (type === 'IDAT') {
      idatParts.push(buf.subarray(dataStart, dataEnd));
    }
    chunks++;
    offset = dataEnd + 4;
    if (type === 'IEND') {
      sawIend = true;
      break;
    }
  }
  if (!sawIhdr) {
    problems.push('missing IHDR');
  }
  if (idatParts.length === 0) {
    problems.push('missing IDAT');
  }
  if (!sawIend) {
    problems.push('missing IEND');
  }
  if (offset !== buf.length && sawIend) {
    problems.push('trailing bytes after IEND: ' + (buf.length - offset));
  }

  if (ihdr !== null) {
    if (ihdr.width <= 0 || ihdr.height <= 0) {
      problems.push('IHDR has a zero dimension: ' + ihdr.width + 'x' + ihdr.height);
    }
    if (ihdr.bitDepth !== 8) {
      problems.push('bit depth is ' + ihdr.bitDepth + ', expected 8');
    }
    if (ihdr.colorType !== 2) {
      problems.push('color type is ' + ihdr.colorType + ', expected 2 (truecolor RGB)');
    }
    if (ihdr.compression !== 0 || ihdr.filter !== 0 || ihdr.interlace !== 0) {
      problems.push('unsupported compression/filter/interlace method');
    }
    if (idatParts.length > 0 && ihdr.width > 0 && ihdr.height > 0) {
      let raw = null;
      try {
        raw = inflateSync(Buffer.concat(idatParts));
      } catch (error) {
        problems.push('IDAT cannot be inflated: ' + error.message);
      }
      if (raw !== null) {
        const stride = 1 + ihdr.width * 3;
        const expected = stride * ihdr.height;
        if (raw.length !== expected) {
          problems.push('decompressed size is ' + raw.length + ', expected ' + expected);
        } else {
          for (let y = 0; y < ihdr.height; y++) {
            const filter = raw[y * stride];
            if (filter > 4) {
              problems.push('row ' + y + ' uses unknown filter ' + filter);
              break;
            }
          }
        }
      }
    }
  }

  if (problems.length > 0) {
    for (const problem of problems) {
      fail(fileName, problem);
    }
    return null;
  }
  return 'signature ok, IHDR ' + ihdr.width + 'x' + ihdr.height
    + ' (RGB/8bit, non-interlaced), chunks=' + chunks + ', CRC ok, IDAT inflates to '
    + (ihdr.height * (1 + ihdr.width * 3)) + ' B, IEND present';
}

/* ------------------------------------------------------------------ *
 * 主流程
 * ------------------------------------------------------------------ */

if (!existsSync(FILE_DIR) || statSync(FILE_DIR).isDirectory() === false) {
  console.error('[check-mock-files] FAIL 产物目录不存在：' + FILE_DIR.replace(/\\/g, '/'));
  process.exit(2);
}

const present = EXPECTED.filter((entry) => existsSync(join(FILE_DIR, entry.fileName)));
if (present.length === 0) {
  console.error('[check-mock-files] FAIL 一个样例文件都没有，空跑会被误判为通过，拒绝放行：'
    + FILE_DIR.replace(/\\/g, '/'));
  process.exit(2);
}

console.log('[check-mock-files] dir: ' + FILE_DIR.replace(/\\/g, '/'));

for (const entry of EXPECTED) {
  const path = join(FILE_DIR, entry.fileName);
  if (!existsSync(path)) {
    fail(entry.fileName, 'file is missing');
    continue;
  }
  const buf = readFileSync(path);
  if (buf.length === 0) {
    fail(entry.fileName, 'file is empty');
    continue;
  }
  let detail = null;
  if (entry.kind === 'pdf') {
    detail = checkPdf(entry.fileName, buf);
  } else if (entry.kind === 'png') {
    detail = checkPng(entry.fileName, buf);
  } else {
    detail = checkPptx(entry.fileName, buf);
  }
  if (detail !== null) {
    pass(entry.fileName + ' (' + entry.contentType + ', ' + buf.length + ' B)', detail);
  }
}

// 三处映射（MockData.mockFiles() 的 mock=NNN → MockFileBlobs.ets → 磁盘上的文件名）
// 最容易在改动时脱节，所以在这里钉一下。
if (existsSync(BLOBS_SOURCE)) {
  const blobs = readFileSync(BLOBS_SOURCE, 'utf8');
  for (const entry of EXPECTED) {
    expect('MockFileBlobs.ets', blobs.indexOf(entry.fileName) >= 0,
      'does not mention ' + entry.fileName + ' (three-way mapping drifted?)');
  }
} else {
  fail('MockFileBlobs.ets', 'not found at ' + BLOBS_SOURCE.replace(/\\/g, '/'));
}

if (failures.length > 0) {
  console.log('[check-mock-files] RESULT: FAIL (' + failures.length + ' problem(s))');
  process.exit(1);
}
console.log('[check-mock-files] RESULT: PASS (' + EXPECTED.length + ' files)');
