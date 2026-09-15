#!/usr/bin/env node
/*
 * Mock 样例文件的**生成器**（scripts）。
 *
 * ## 为什么需要它
 *
 * mock 模式下点开「文件」要**真的落盘出真文件**（预览 / 交给系统打开 / 分享 / 缓存命中
 * 全都要走通），而 mock 分支一行网络请求都不发。于是这 4 个样例文件必须**打进包里**：
 *   entry/src/main/resources/rawfile/mock-files/
 * 并且内容要**真能打开**：PDF 必须是 PDFKit 能 loadDocument 出 PARSE_SUCCESS 的合法 PDF，
 * PPTX 必须是结构完整的 OOXML 包。手写二进制不可维护 ⇒ 生成器 + 校验器成对提交
 * （校验器：scripts/check-mock-files.mjs）。
 *
 * ## 与 MockData / MockFileBlobs 的对应关系（**三处必须一致**）
 *
 *   mock=101  mock-course-syllabus.pdf      数据结构 / 课程大纲
 *   mock=102  mock-homework-1-answers.pdf   数据结构 / 第一次作业参考答案
 *   mock=103  mock-physics-lab-manual.pdf   大学物理（1） / 实验指导书
 *   mock=104  mock-lecture-notes-3.pptx     马克思主义基本原理 / 课堂讲义（第三讲）
 *
 * id 与 rawfile 路径的对应写在 entry/src/main/ets/data/mock/MockFileBlobs.ets；
 * 而 mock=NNN 这个 id 来自 data/mock/MockData.ets 的 mockFiles().downloadUrl。
 * 本文件是 Node 脚本，**不 import ArkTS**，所以改这里必须同时改 MockFileBlobs.ets。
 *
 * ## 输出的确定性（幂等）
 *
 * 无时间戳、无随机数、ZIP 条目用 STORE（不压缩）⇒ 同样的输入在任何机器 / 任何 Node
 * 版本上都得到**逐字节相同**的输出。所以本脚本可以随时重跑、可以直接覆盖旧产物：
 *   node scripts/gen-mock-files.mjs
 * check-mock-files.mjs 校验的是**结构**（不是"与重新生成的结果逐字节相同"），
 * 这样换一台机器也不会造成假红。
 *
 * ## PDF 正文为什么是 ASCII
 *
 * PDF 的标准 14 字体（Helvetica）只有 WinAnsi 编码，页面上要出现中文就必须**内嵌 CJK
 * 子集字体**；而生成器不依赖任何系统字体文件（那会毁掉可复现性）。所以 PDF 正文用 ASCII
 * （英文课程名 + mock id + 正文若干行），保证"在任何阅读器里都真的看得见东西"。
 * **PPTX 没有这个限制**（XML 本身是 UTF-8），所以那份讲义里是中文。
 *
 * ## 用法
 *
 *   node scripts/gen-mock-files.mjs
 * 退出码：0 = 全部写出；非零 = 写失败（异常直接冒泡）。
 */

import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const OUT_DIR = join(REPO_ROOT, 'entry', 'src', 'main', 'resources', 'rawfile', 'mock-files');

/** 与 MockFileBlobs.ets 的 contentType 逐字一致。 */
const PDF_CONTENT_TYPE = 'application/pdf';
const PPTX_CONTENT_TYPE =
  'application/vnd.openxmlformats-officedocument.presentationml.presentation';

/* ------------------------------------------------------------------ *
 * 一、PDF（未压缩内容流，xref 偏移逐字节精确）
 * ------------------------------------------------------------------ */

/** PDF 字面量字符串的转义（反斜杠与左右圆括号三个字符）。 */
function pdfString(text) {
  return '(' + text.replace(/\\/g, '\\\\').replace(/\(/g, '\\(').replace(/\)/g, '\\)') + ')';
}

/**
 * 一页的内容流。
 *
 * 行坐标用**绝对**文本矩阵命令 Tm（形如 1 0 0 1 72 y），不用相对 Td：绝对坐标让
 * "文字落在页面里"这件事可以用眼睛或解析器直接核对，不依赖对文本行矩阵累积的理解。
 * @param lines [{ text, size, bold }]
 */
function pdfContentStream(lines) {
  const out = ['BT'];
  let y = 780;
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const size = line.size === undefined ? 12 : line.size;
    if (i > 0) {
      y -= Math.round(size * 1.8);
    }
    out.push('/' + (line.bold ? 'F2' : 'F1') + ' ' + size + ' Tf');
    out.push('1 0 0 1 72 ' + y + ' Tm');
    out.push(pdfString(line.text) + ' Tj');
  }
  out.push('ET');
  return out.join('\n') + '\n';
}

/**
 * 把若干页序列化成一份合法 PDF。
 *
 * 对象编号固定（不依赖遍历顺序，便于校验器按页对象检查）：
 *   1 = Catalog，2 = Pages，3 = /F1 Helvetica，4 = /F2 Helvetica-Bold，
 *   5,7,9,… = Page，6,8,10,… = 各自的 Contents。
 * @param pages 每页的行数组
 */
function buildPdf(pages) {
  const pageCount = pages.length;
  const totalObjects = 4 + pageCount * 2; // 编号 1..totalObjects
  const bodies = new Array(totalObjects + 1).fill('');

  bodies[1] = '<< /Type /Catalog /Pages 2 0 R >>';
  const kids = [];
  for (let i = 0; i < pageCount; i++) {
    kids.push((5 + i * 2) + ' 0 R');
  }
  bodies[2] = '<< /Type /Pages /Kids [' + kids.join(' ') + '] /Count ' + pageCount + ' >>';
  bodies[3] = '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica '
    + '/Encoding /WinAnsiEncoding >>';
  bodies[4] = '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold '
    + '/Encoding /WinAnsiEncoding >>';

  for (let i = 0; i < pageCount; i++) {
    const pageNo = 5 + i * 2;
    const contentNo = pageNo + 1;
    const content = Buffer.from(pdfContentStream(pages[i]), 'latin1');
    bodies[pageNo] = '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] '
      + '/Resources << /Font << /F1 3 0 R /F2 4 0 R >> >> '
      + '/Contents ' + contentNo + ' 0 R >>';
    bodies[contentNo] = '<< /Length ' + content.length + ' >>\nstream\n'
      + content.toString('latin1') + 'endstream';
  }

  const chunks = [];
  let offset = 0;
  const offsets = new Array(totalObjects + 1).fill(0);
  const push = (buf) => {
    chunks.push(buf);
    offset += buf.length;
  };
  // 头部：版本 + 二进制标记注释（规范建议，且让"这是二进制文件"对工具可见）。
  push(Buffer.from('%PDF-1.4\n%\xE2\xE3\xCF\xD3\n', 'latin1'));
  for (let n = 1; n <= totalObjects; n++) {
    offsets[n] = offset;
    push(Buffer.from(n + ' 0 obj\n', 'latin1'));
    push(Buffer.from(bodies[n], 'latin1'));
    push(Buffer.from('\nendobj\n', 'latin1'));
  }
  const xrefOffset = offset;
  // xref 每行**恰好 20 字节**（10 位偏移 + 空格 + 5 位世代 + 空格 + 类型 + 空格 + 换行）。
  let xref = 'xref\n0 ' + (totalObjects + 1) + '\n0000000000 65535 f \n';
  for (let n = 1; n <= totalObjects; n++) {
    xref += String(offsets[n]).padStart(10, '0') + ' 00000 n \n';
  }
  xref += 'trailer\n<< /Size ' + (totalObjects + 1) + ' /Root 1 0 R >>\n'
    + 'startxref\n' + xrefOffset + '\n%%EOF\n';
  push(Buffer.from(xref, 'latin1'));
  return Buffer.concat(chunks);
}

/** 一份样例 PDF 的页面内容（标题 + 课程/文件身份 + 几行正文 + 页码）。 */
function samplePdfPages(spec) {
  const pages = [];
  for (let page = 1; page <= spec.pageCount; page++) {
    const lines = [];
    lines.push({ text: 'learnOH mock sample file', size: 10 });
    lines.push({ text: spec.title, size: 20, bold: true });
    lines.push({ text: 'Course: ' + spec.course, size: 12 });
    lines.push({ text: 'Teacher: ' + spec.teacher, size: 12 });
    lines.push({ text: 'File id: ' + spec.fileId + '   (mock=' + spec.mockId + ')', size: 10 });
    lines.push({ text: 'Sample index: page ' + page + ' of ' + spec.pageCount, size: 10 });
    const section = spec.sections[page - 1];
    for (let i = 0; i < section.length; i++) {
      lines.push({ text: section[i], size: 11 });
    }
    pages.push(lines);
  }
  return pages;
}

/* ------------------------------------------------------------------ *
 * 二、ZIP（STORE，无数据描述符；[Content_Types].xml 必须是第一个成员）
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

/**
 * 打一个 STORE 的 ZIP。
 *
 * 为什么用 STORE 而不是 DEFLATE：① 输出与 zlib 版本无关 ⇒ 真正逐字节可复现；
 * ② 校验器不解压就能核对每个成员的长度与 CRC。ZIP 规范里 STORE 是完全合法的，
 * OOXML 只要求"是一个 ZIP 包"。
 * @param entries [{ name, data: Buffer }]（顺序 = 本地头顺序 = 成员顺序）
 */
function buildZip(entries) {
  const localParts = [];
  const centralParts = [];
  let offset = 0;
  for (const entry of entries) {
    const name = Buffer.from(entry.name, 'utf8');
    const data = entry.data;
    const crc = crc32(data);
    const localOffset = offset;
    const header = Buffer.alloc(30);
    header.writeUInt32LE(0x04034b50, 0);
    header.writeUInt16LE(20, 4);      // version needed to extract
    header.writeUInt16LE(0x0800, 6);  // 通用标志：文件名是 UTF-8
    header.writeUInt16LE(0, 8);       // method = 0 (stored)
    header.writeUInt16LE(0, 10);      // mod time = 00:00:00
    header.writeUInt16LE(0x0021, 12); // mod date = 1980-01-01（固定值 ⇒ 可复现）
    header.writeUInt32LE(crc, 14);
    header.writeUInt32LE(data.length, 18);
    header.writeUInt32LE(data.length, 22);
    header.writeUInt16LE(name.length, 26);
    header.writeUInt16LE(0, 28);      // extra field length
    localParts.push(header, name, data);

    const cd = Buffer.alloc(46);
    cd.writeUInt32LE(0x02014b50, 0);
    cd.writeUInt16LE(20, 4);          // version made by
    cd.writeUInt16LE(20, 6);          // version needed
    cd.writeUInt16LE(0x0800, 8);
    cd.writeUInt16LE(0, 10);
    cd.writeUInt16LE(0, 12);
    cd.writeUInt16LE(0x0021, 14);
    cd.writeUInt32LE(crc, 16);
    cd.writeUInt32LE(data.length, 20);
    cd.writeUInt32LE(data.length, 24);
    cd.writeUInt16LE(name.length, 28);
    cd.writeUInt16LE(0, 30);          // extra length
    cd.writeUInt16LE(0, 32);          // comment length
    cd.writeUInt16LE(0, 34);          // disk number start
    cd.writeUInt16LE(0, 36);          // internal attributes
    cd.writeUInt32LE(0, 38);          // external attributes
    cd.writeUInt32LE(localOffset, 42);
    centralParts.push(cd, name);

    offset += header.length + name.length + data.length;
  }
  const localBuf = Buffer.concat(localParts);
  const centralBuf = Buffer.concat(centralParts);
  const eocd = Buffer.alloc(22);
  eocd.writeUInt32LE(0x06054b50, 0);
  eocd.writeUInt16LE(0, 4);
  eocd.writeUInt16LE(0, 6);
  eocd.writeUInt16LE(entries.length, 8);
  eocd.writeUInt16LE(entries.length, 10);
  eocd.writeUInt32LE(centralBuf.length, 12);
  eocd.writeUInt32LE(localBuf.length, 16);
  eocd.writeUInt16LE(0, 20);
  return Buffer.concat([localBuf, centralBuf, eocd]);
}

/* ------------------------------------------------------------------ *
 * 三、PPTX（OOXML 最小但完整的一套部件）
 * ------------------------------------------------------------------ */

const NS_A = 'http://schemas.openxmlformats.org/drawingml/2006/main';
const NS_R = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const NS_P = 'http://schemas.openxmlformats.org/presentationml/2006/main';
const NS_CT = 'http://schemas.openxmlformats.org/package/2006/content-types';
const NS_REL = 'http://schemas.openxmlformats.org/package/2006/relationships';
const RT = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships/';
const XML_HEAD = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n';

/** XML 文本节点的转义（& < >）。 */
function escapeXml(text) {
  return text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

/** 形状树 p:spTree 里必须有的一对空节点（每组形状的前两个子元素）。 */
const SPTREE_HEAD = ''
  + '<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>'
  + '<p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/>'
  + '<a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>';

/** 一个带占位符的文本框形状。 */
function textShape(id, name, placeholderType, placeholderIdx, x, y, cx, cy, paragraphs) {
  const ph = placeholderIdx === undefined
    ? '<p:ph type="' + placeholderType + '"/>'
    : '<p:ph type="' + placeholderType + '" idx="' + placeholderIdx + '"/>';
  let body = '';
  for (const runs of paragraphs) {
    body += '<a:p>';
    for (const run of runs) {
      const size = run.size === undefined ? 1800 : run.size;
      body += '<a:r><a:rPr lang="zh-CN" altLang="en-US" sz="' + size + '"'
        + (run.bold ? ' b="1"' : '') + ' dirty="0"/><a:t>' + escapeXml(run.text) + '</a:t></a:r>';
    }
    body += '<a:endParaRPr lang="zh-CN" altLang="en-US" dirty="0"/></a:p>';
  }
  return '<p:sp><p:nvSpPr><p:cNvPr id="' + id + '" name="' + name + '"/>'
    + '<p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr><p:nvPr>' + ph + '</p:nvPr></p:nvSpPr>'
    + '<p:spPr><a:xfrm><a:off x="' + x + '" y="' + y + '"/><a:ext cx="' + cx + '" cy="' + cy + '"/>'
    + '</a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></p:spPr>'
    + '<p:txBody><a:bodyPr wrap="square" rtlCol="0"><a:normAutofit/></a:bodyPr>'
    + '<a:lstStyle/>' + body + '</p:txBody></p:sp>';
}

/** 一套最小但**结构完整**的 OOXML 部件（顺序：内容类型表必须第一）。 */
function pptxParts() {
  const contentTypes = XML_HEAD
    + '<Types xmlns="' + NS_CT + '">'
    + '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
    + '<Default Extension="xml" ContentType="application/xml"/>'
    + '<Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/>'
    + '<Override PartName="/ppt/slideMasters/slideMaster1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml"/>'
    + '<Override PartName="/ppt/slideLayouts/slideLayout1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml"/>'
    + '<Override PartName="/ppt/slides/slide1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>'
    + '<Override PartName="/ppt/theme/theme1.xml" ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/>'
    + '</Types>\n';

  const rootRels = XML_HEAD
    + '<Relationships xmlns="' + NS_REL + '">'
    + '<Relationship Id="rId1" Type="' + RT + 'officeDocument" Target="ppt/presentation.xml"/>'
    + '</Relationships>\n';

  const presentation = XML_HEAD
    + '<p:presentation xmlns:a="' + NS_A + '" xmlns:r="' + NS_R + '" xmlns:p="' + NS_P + '"'
    + ' saveSubsetFonts="1">'
    + '<p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rId1"/></p:sldMasterIdLst>'
    + '<p:sldIdLst><p:sldId id="256" r:id="rId2"/></p:sldIdLst>'
    + '<p:sldSz cx="12192000" cy="6858000"/>'
    + '<p:notesSz cx="6858000" cy="9144000"/>'
    + '<p:defaultTextStyle><a:defPPr><a:defRPr lang="zh-CN"/></a:defPPr></p:defaultTextStyle>'
    + '</p:presentation>\n';

  const presentationRels = XML_HEAD
    + '<Relationships xmlns="' + NS_REL + '">'
    + '<Relationship Id="rId1" Type="' + RT + 'slideMaster" Target="slideMasters/slideMaster1.xml"/>'
    + '<Relationship Id="rId2" Type="' + RT + 'slide" Target="slides/slide1.xml"/>'
    + '<Relationship Id="rId3" Type="' + RT + 'theme" Target="theme/theme1.xml"/>'
    + '</Relationships>\n';

  const slideMaster = XML_HEAD
    + '<p:sldMaster xmlns:a="' + NS_A + '" xmlns:r="' + NS_R + '" xmlns:p="' + NS_P + '">'
    + '<p:cSld>'
    + '<p:bg><p:bgRef idx="1001"><a:schemeClr val="bg1"/></p:bgRef></p:bg>'
    + '<p:spTree>' + SPTREE_HEAD
    + textShape(2, 'Title Placeholder 1', 'title', undefined, 457200, 274638, 8229600, 1143000,
      [[{ text: 'Click to edit Master title style', size: 2800, bold: true }]])
    + '</p:spTree>'
    + '</p:cSld>'
    + '<p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" accent2="accent2"'
    + ' accent3="accent3" accent4="accent4" accent5="accent5" accent6="accent6"'
    + ' hlink="hlink" folHlink="folHlink"/>'
    + '<p:sldLayoutIdLst><p:sldLayoutId id="2147483649" r:id="rId1"/></p:sldLayoutIdLst>'
    + '<p:txStyles><p:titleStyle/><p:bodyStyle/><p:otherStyle/></p:txStyles>'
    + '</p:sldMaster>\n';

  const slideMasterRels = XML_HEAD
    + '<Relationships xmlns="' + NS_REL + '">'
    + '<Relationship Id="rId1" Type="' + RT + 'slideLayout" Target="../slideLayouts/slideLayout1.xml"/>'
    + '<Relationship Id="rId2" Type="' + RT + 'theme" Target="../theme/theme1.xml"/>'
    + '</Relationships>\n';

  const slideLayout = XML_HEAD
    + '<p:sldLayout xmlns:a="' + NS_A + '" xmlns:r="' + NS_R + '" xmlns:p="' + NS_P + '"'
    + ' type="blank" preserve="1">'
    + '<p:cSld name="Blank"><p:spTree>' + SPTREE_HEAD + '</p:spTree></p:cSld>'
    + '<p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>'
    + '</p:sldLayout>\n';

  const slideLayoutRels = XML_HEAD
    + '<Relationships xmlns="' + NS_REL + '">'
    + '<Relationship Id="rId1" Type="' + RT + 'slideMaster" Target="../slideMasters/slideMaster1.xml"/>'
    + '</Relationships>\n';

  const slide = XML_HEAD
    + '<p:sld xmlns:a="' + NS_A + '" xmlns:r="' + NS_R + '" xmlns:p="' + NS_P + '">'
    + '<p:cSld><p:spTree>' + SPTREE_HEAD
    + textShape(2, 'Title 1', 'title', undefined, 457200, 274638, 8229600, 1143000,
      [[{ text: '课堂讲义（第三讲）', size: 3200, bold: true }]])
    + textShape(3, 'Content Placeholder 2', 'body', 1, 457200, 1600200, 8229600, 4525963, [
      [{ text: '马克思主义基本原理', size: 2000, bold: true }],
      [{ text: '课程教师：赵磊' }, { text: '  文件编号：mock-wjid-104' }],
      [{ text: '本文件是 learnOH Mock 模式下打进包里的样例讲义（mock=104）。' }],
      [{ text: '它存在的目的：mock 登录后点开「文件」也能真的落盘出可打开的文件，' }],
      [{ text: '于是预览 / 交给系统打开 / 分享 / 缓存命中全部走通，且一行网络请求都不发。' }],
      [{ text: '第三讲提纲：' }],
      [{ text: '  1. 实践与认识的辩证关系' }],
      [{ text: '  2. 社会存在与社会意识' }],
      [{ text: '  3. 课下阅读：教材第三章 3.1 - 3.3 节' }],
      [{ text: '' }],
      [{ text: '（本页文字由 scripts/gen-mock-files.mjs 生成，结构校验见 scripts/check-mock-files.mjs）' }]
    ])
    + '</p:spTree></p:cSld>'
    + '<p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>'
    + '</p:sld>\n';

  const slideRels = XML_HEAD
    + '<Relationships xmlns="' + NS_REL + '">'
    + '<Relationship Id="rId1" Type="' + RT + 'slideLayout" Target="../slideLayouts/slideLayout1.xml"/>'
    + '</Relationships>\n';

  const theme = XML_HEAD
    + '<a:theme xmlns:a="' + NS_A + '" name="learnOH Mock Theme"><a:themeElements>'
    + '<a:clrScheme name="learnOH">'
    + '<a:dk1><a:sysClr val="windowText" lastClr="000000"/></a:dk1>'
    + '<a:lt1><a:sysClr val="window" lastClr="FFFFFF"/></a:lt1>'
    + '<a:dk2><a:srgbClr val="44546A"/></a:dk2>'
    + '<a:lt2><a:srgbClr val="E7E6E6"/></a:lt2>'
    + '<a:accent1><a:srgbClr val="4472C4"/></a:accent1>'
    + '<a:accent2><a:srgbClr val="ED7D31"/></a:accent2>'
    + '<a:accent3><a:srgbClr val="A5A5A5"/></a:accent3>'
    + '<a:accent4><a:srgbClr val="FFC000"/></a:accent4>'
    + '<a:accent5><a:srgbClr val="5B9BD5"/></a:accent5>'
    + '<a:accent6><a:srgbClr val="70AD47"/></a:accent6>'
    + '<a:hlink><a:srgbClr val="0563C1"/></a:hlink>'
    + '<a:folHlink><a:srgbClr val="954F72"/></a:folHlink>'
    + '</a:clrScheme>'
    + '<a:fontScheme name="learnOH">'
    + '<a:majorFont><a:latin typeface="Calibri Light"/><a:ea typeface=""/><a:cs typeface=""/></a:majorFont>'
    + '<a:minorFont><a:latin typeface="Calibri"/><a:ea typeface=""/><a:cs typeface=""/></a:minorFont>'
    + '</a:fontScheme>'
    + '<a:fmtScheme name="learnOH">'
    + '<a:fillStyleLst>'
    + '<a:solidFill><a:schemeClr val="phClr"/></a:solidFill>'
    + '<a:gradFill rotWithShape="1"><a:gsLst>'
    + '<a:gs pos="0"><a:schemeClr val="phClr"><a:lumMod val="110000"/><a:satMod val="105000"/>'
    + '<a:tint val="67000"/></a:schemeClr></a:gs>'
    + '<a:gs pos="50000"><a:schemeClr val="phClr"><a:lumMod val="105000"/><a:satMod val="103000"/>'
    + '<a:tint val="73000"/></a:schemeClr></a:gs>'
    + '<a:gs pos="100000"><a:schemeClr val="phClr"><a:lumMod val="105000"/><a:satMod val="109000"/>'
    + '<a:tint val="81000"/></a:schemeClr></a:gs>'
    + '</a:gsLst><a:lin ang="5400000" scaled="0"/></a:gradFill>'
    + '<a:gradFill rotWithShape="1"><a:gsLst>'
    + '<a:gs pos="0"><a:schemeClr val="phClr"><a:satMod val="103000"/><a:lumMod val="102000"/>'
    + '<a:tint val="94000"/></a:schemeClr></a:gs>'
    + '<a:gs pos="50000"><a:schemeClr val="phClr"><a:satMod val="110000"/><a:lumMod val="100000"/>'
    + '<a:shade val="100000"/></a:schemeClr></a:gs>'
    + '<a:gs pos="100000"><a:schemeClr val="phClr"><a:lumMod val="99000"/><a:satMod val="120000"/>'
    + '<a:shade val="78000"/></a:schemeClr></a:gs>'
    + '</a:gsLst><a:lin ang="5400000" scaled="0"/></a:gradFill>'
    + '</a:fillStyleLst>'
    + '<a:lnStyleLst>'
    + '<a:ln w="6350" cap="flat" cmpd="sng" algn="ctr"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill>'
    + '<a:prstDash val="solid"/><a:miter lim="800000"/></a:ln>'
    + '<a:ln w="12700" cap="flat" cmpd="sng" algn="ctr"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill>'
    + '<a:prstDash val="solid"/><a:miter lim="800000"/></a:ln>'
    + '<a:ln w="19050" cap="flat" cmpd="sng" algn="ctr"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill>'
    + '<a:prstDash val="solid"/><a:miter lim="800000"/></a:ln>'
    + '</a:lnStyleLst>'
    + '<a:effectStyleLst>'
    + '<a:effectStyle><a:effectLst/></a:effectStyle>'
    + '<a:effectStyle><a:effectLst/></a:effectStyle>'
    + '<a:effectStyle><a:effectLst><a:outerShdw blurRad="57150" dist="19050" dir="5400000"'
    + ' algn="ctr" rotWithShape="0"><a:srgbClr val="000000"><a:alpha val="63000"/></a:srgbClr>'
    + '</a:outerShdw></a:effectLst></a:effectStyle>'
    + '</a:effectStyleLst>'
    + '<a:bgFillStyleLst>'
    + '<a:solidFill><a:schemeClr val="phClr"/></a:solidFill>'
    + '<a:solidFill><a:schemeClr val="phClr"><a:tint val="95000"/><a:satMod val="170000"/>'
    + '</a:schemeClr></a:solidFill>'
    + '<a:gradFill rotWithShape="1"><a:gsLst>'
    + '<a:gs pos="0"><a:schemeClr val="phClr"><a:tint val="93000"/><a:satMod val="150000"/>'
    + '<a:shade val="98000"/><a:lumMod val="102000"/></a:schemeClr></a:gs>'
    + '<a:gs pos="50000"><a:schemeClr val="phClr"><a:tint val="98000"/><a:satMod val="130000"/>'
    + '<a:shade val="90000"/><a:lumMod val="103000"/></a:schemeClr></a:gs>'
    + '<a:gs pos="100000"><a:schemeClr val="phClr"><a:shade val="63000"/><a:satMod val="120000"/>'
    + '</a:schemeClr></a:gs>'
    + '</a:gsLst><a:lin ang="5400000" scaled="0"/></a:gradFill>'
    + '</a:bgFillStyleLst>'
    + '</a:fmtScheme>'
    + '</a:themeElements><a:objectDefaults/><a:extraClrSchemeLst/></a:theme>\n';

  // 顺序即成员顺序：[Content_Types].xml **必须第一个**。
  const parts = [
    { name: '[Content_Types].xml', text: contentTypes },
    { name: '_rels/.rels', text: rootRels },
    { name: 'ppt/presentation.xml', text: presentation },
    { name: 'ppt/_rels/presentation.xml.rels', text: presentationRels },
    { name: 'ppt/slideMasters/slideMaster1.xml', text: slideMaster },
    { name: 'ppt/slideMasters/_rels/slideMaster1.xml.rels', text: slideMasterRels },
    { name: 'ppt/slideLayouts/slideLayout1.xml', text: slideLayout },
    { name: 'ppt/slideLayouts/_rels/slideLayout1.xml.rels', text: slideLayoutRels },
    { name: 'ppt/slides/slide1.xml', text: slide },
    { name: 'ppt/slides/_rels/slide1.xml.rels', text: slideRels },
    { name: 'ppt/theme/theme1.xml', text: theme }
  ];
  return parts.map((part) => ({ name: part.name, data: Buffer.from(part.text, 'utf8') }));
}

/* ------------------------------------------------------------------ *
 * 四、四个样例文件（mock=101..104，与 MockData.mockFiles() 一一对应）
 * ------------------------------------------------------------------ */

const SYLLABUS = samplePdfPages({
  mockId: '101',
  fileId: 'mock-wjid-101',
  title: 'Course Syllabus',
  course: 'Data Structures',
  teacher: 'Li Qiang',
  pageCount: 3,
  sections: [
    [
      '1. Course overview',
      '   This sample PDF is produced by scripts/gen-mock-files.mjs and bundled',
      '   into the app as entry/src/main/resources/rawfile/mock-files/.',
      '   It exists so that a mock-mode download writes a real, openable file.',
      '2. Prerequisites',
      '   Programming fundamentals. No prior C experience is required.'
    ],
    [
      '3. Schedule (16 weeks)',
      '   Weeks 1-4   Lists, stacks and queues',
      '   Weeks 5-8   Trees, heaps and balanced search trees',
      '   Weeks 9-12  Graphs, shortest paths and spanning trees',
      '   Weeks 13-16 Sorting, hashing and an introduction to complexity',
      '4. Midterm',
      '   Week 9, Wednesday 19:00 - 21:00. Room to be announced.'
    ],
    [
      '5. Assessment',
      '   Homework            40%',
      '   Midterm             25%',
      '   Final examination   35%',
      '6. Textbook',
      '   Mark Allen Weiss, Data Structures and Algorithm Analysis.',
      '7. Contact',
      '   Li Qiang, Department of Computer Science. Office hours by appointment.'
    ]
  ]
});

const HOMEWORK = samplePdfPages({
  mockId: '102',
  fileId: 'mock-wjid-102',
  title: 'Homework 1 Reference Answers',
  course: 'Data Structures',
  teacher: 'Li Qiang',
  pageCount: 2,
  sections: [
    [
      'Exercise 1 (linear list)',
      '   A singly linked list with a head node supports insertion at the front',
      '   in O(1) and deletion by value in O(n). The reference answer keeps a',
      '   tail pointer so that appending is also O(1).',
      'Exercise 3 (complexity)',
      '   The loop executes n + (n-1) + ... + 1 times, therefore T(n) = O(n^2).'
    ],
    [
      'Exercise 5 (implementation notes)',
      '   Remember to release every node that is unlinked; the reference',
      '   implementation returns the removed element and leaves the list valid.',
      'Grading notes',
      '   Full credit requires the complexity argument, not only the code.'
    ]
  ]
});

const LAB_MANUAL = samplePdfPages({
  mockId: '103',
  fileId: 'mock-wjid-103',
  title: 'Physics Lab Manual',
  course: 'University Physics (1)',
  teacher: 'Wang Min',
  pageCount: 4,
  sections: [
    [
      'Lab 1  Measurement and error analysis',
      '   Goals: use a vernier caliper and a micrometer screw gauge; report a',
      '   measurement with its absolute and relative uncertainty.',
      '   Apparatus: steel cylinder, vernier caliper, micrometer, balance.'
    ],
    [
      'Lab 2  Uniformly accelerated motion',
      '   Goals: measure the acceleration of a cart on an inclined track and',
      '   compare it with the value predicted from the incline angle.',
      '   Apparatus: air track, photogates, digital timer.'
    ],
    [
      'Lab 3  Conservation of momentum',
      '   Goals: verify momentum conservation in a two-body collision and',
      '   classify the collision as elastic or inelastic from the energy loss.',
      '   Apparatus: air track, two carts, photogates, electronic balance.'
    ],
    [
      'Lab 4  Simple harmonic motion',
      '   Goals: measure the period of a spring pendulum as a function of the',
      '   suspended mass and extract the spring constant from the slope.',
      '   Report: every lab report needs data tables, error bars and a short',
      '   discussion of the dominant source of uncertainty.'
    ]
  ]
});

const FILES = [
  { fileName: 'mock-course-syllabus.pdf', data: buildPdf(SYLLABUS), contentType: PDF_CONTENT_TYPE },
  { fileName: 'mock-homework-1-answers.pdf', data: buildPdf(HOMEWORK), contentType: PDF_CONTENT_TYPE },
  { fileName: 'mock-physics-lab-manual.pdf', data: buildPdf(LAB_MANUAL), contentType: PDF_CONTENT_TYPE },
  { fileName: 'mock-lecture-notes-3.pptx', data: buildZip(pptxParts()), contentType: PPTX_CONTENT_TYPE }
];

mkdirSync(OUT_DIR, { recursive: true });
for (const file of FILES) {
  const target = join(OUT_DIR, file.fileName);
  writeFileSync(target, file.data);
  console.log('wrote ' + target.replace(/\\/g, '/') + '  ' + file.data.length + ' bytes  '
    + file.contentType);
}
console.log('mock sample files: ' + FILES.length + ' written to ' + OUT_DIR.replace(/\\/g, '/'));
