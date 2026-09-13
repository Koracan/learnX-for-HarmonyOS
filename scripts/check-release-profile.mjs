#!/usr/bin/env node
/**
 * 上架前的 Profile 体检（统筹新增，2026-09-13）。
 *
 * 起因（实测）：AGC「上传产品」报 **ACL permission consistency**，而本地构建一路绿灯 ——
 * 因为这条校验只发生在 AGC 侧：`module.json5` 请求的**受限 ACL 权限**必须出现在
 * **签名所用 Profile 的 `acls.allowed-acls`** 里。Profile 是华为签发的二进制（PKCS#7/CMS），
 * 不看一眼根本不知道里面有没有那条权限（`type`/`acls` 一律靠解出来的 JSON 说话）。
 *
 * 本脚本做四件事（都不碰设备、不碰网络）：
 *   1. 解出**发布签名配置**（`signingConfigs` 里名为 `release` 的那份）所指 Profile 的 JSON：
 *      `type` / `app-distribution-type` / `bundle-name` / `app-identifier` / `acls.allowed-acls`。
 *   2. 硬校验：必须是 `type=release` + `app_gallery`，`bundle-name` 必须等于 `AppScope/app.json5` 的 `bundleName`。
 *   3. 证书绑定：Profile 内嵌的 `distribution-certificate` 必须与 `material.certpath` 里的**叶子证书**
 *      逐字节同一份（换了证书 ⇒ fingerprint 变 ⇒ 按指纹鉴权的开放能力要重新配指纹）。
 *   4. ACL 一致性：`module.json5` 请求的权限里，凡在 RESTRICTED 表内的，必须出现在 `allowed-acls`。
 *      其余请求权限逐条列出并标注是否在 `allowed-acls` 里，交给人工判断（SDK 里没有"哪些权限受限"的清单）。
 *
 * 用法：
 *   node scripts/check-release-profile.mjs                       # 检查 release 签名配置所指的 Profile
 *   node scripts/check-release-profile.mjs --profile <某.p7b>     # 检查刚下载、还没写进 build-profile 的那份
 *   node scripts/check-release-profile.mjs --quiet                # 只打结论
 * 退出码：0 = 可以打发布包；1 = 有问题（会逐条说明）；2 = 跑不起来（缺文件 / 没有 release 签名配置）。
 *
 * 注意：本脚本**不进四条门禁** —— 它依赖 `keys/`（已 gitignore）与具体签名配置，别人机器上跑不了。
 */

import { readFileSync, existsSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { dirname, isAbsolute, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');

/** 已知需要 ACL 放行的受限权限（来源：华为「受限权限」清单 + 本工程实测）。发现新的就往这里加一条。 */
const RESTRICTED = new Set([
  'ohos.permission.READ_WRITE_DOWNLOAD_DIRECTORY',
  'ohos.permission.READ_WRITE_DOCUMENTS_DIRECTORY',
]);

const argv = process.argv.slice(2);
function argValue(name) {
  const i = argv.indexOf(name);
  return i >= 0 && i + 1 < argv.length ? argv[i + 1] : null;
}
const quiet = argv.includes('--quiet');
const profileOverride = argValue('--profile');

const problems = [];
const fail = (msg) => problems.push(msg);
const say = (msg) => { if (!quiet) console.log(msg); };

/** 去掉行注释与块注释（保留字符串内的斜杠），让 .json5 能被 JSON.parse 吃下。 */
function stripJsonComments(text) {
  let out = '';
  let inStr = false;
  let esc = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (inStr) {
      out += c;
      if (esc) esc = false;
      else if (c === '\\') esc = true;
      else if (c === '"') inStr = false;
      continue;
    }
    if (c === '"') { inStr = true; out += c; continue; }
    if (c === '/' && text[i + 1] === '/') { while (i < text.length && text[i] !== '\n') i++; out += '\n'; continue; }
    if (c === '/' && text[i + 1] === '*') {
      i += 2;
      while (i < text.length && !(text[i] === '*' && text[i + 1] === '/')) i++;
      i += 1;
      continue;
    }
    out += c;
  }
  return out;
}

function readJson5(path) {
  return JSON.parse(stripJsonComments(readFileSync(path, 'utf8')));
}

/** 只解析本脚本要用的 TLV 长度，不建通用 ASN.1 树。 */
function readTlv(buf, pos) {
  if (pos + 2 > buf.length) throw new Error('DER 越界 @' + pos);
  const tag = buf[pos];
  let len = buf[pos + 1];
  let header = 2;
  if (len & 0x80) {
    const n = len & 0x7f;
    if (n === 0 || n > 4) throw new Error('不支持的 DER 长度形式 @' + pos);
    len = 0;
    for (let i = 0; i < n; i++) len = len * 256 + buf[pos + 2 + i];
    header = 2 + n;
  }
  const contentStart = pos + header;
  return { tag, length: len, contentStart, end: contentStart + len };
}

/** CMS SignedData 的 eContent 就是 Profile 的 JSON。 */
function decodeProfileJson(buf) {
  const outer = readTlv(buf, 0);
  let p = outer.contentStart;
  p = readTlv(buf, p).end;                       // contentType OID
  const explicit0 = readTlv(buf, p);             // [0] EXPLICIT SignedData
  if (explicit0.tag !== 0xa0) throw new Error('不是 CMS SignedData（缺 [0]）');
  const signedData = readTlv(buf, explicit0.contentStart);
  let q = signedData.contentStart;
  q = readTlv(buf, q).end;                       // version INTEGER
  q = readTlv(buf, q).end;                       // digestAlgorithms SET
  const encap = readTlv(buf, q);                 // EncapsulatedContentInfo SEQUENCE
  let r = encap.contentStart;
  r = readTlv(buf, r).end;                       // eContentType OID
  const eContent = readTlv(buf, r);              // [0] EXPLICIT
  let s = eContent.contentStart;
  const inner = readTlv(buf, s);
  let json;
  if (inner.tag === 0x04) {
    json = buf.subarray(inner.contentStart, inner.end);
  } else if (inner.tag === 0x24) {               // 构造型 OCTET STRING：拼起来
    const parts = [];
    let t = s;
    while (t < eContent.end) {
      const c = readTlv(buf, t);
      parts.push(buf.subarray(c.contentStart, c.end));
      t = c.end;
    }
    json = Buffer.concat(parts);
  } else {
    throw new Error('eContent 里不是 OCTET STRING（tag=0x' + inner.tag.toString(16) + '）');
  }
  return JSON.parse(json.toString('utf8'));
}

/** 取 PEM 里最后一张证书（叶子）的 DER 指纹。 */
function leafCertSha256(pemText) {
  const pems = pemText.match(/-----BEGIN CERTIFICATE-----[\s\S]*?-----END CERTIFICATE-----/g);
  if (!pems || pems.length === 0) throw new Error('没找到 CERTIFICATE PEM');
  const b64 = pems[pems.length - 1].replace(/-----[^-]+-----/g, '').replace(/\s/g, '');
  return createHash('sha256').update(Buffer.from(b64, 'base64')).digest('hex');
}

function sha256OfPem(pemText) {
  const b64 = pemText.replace(/-----[^-]+-----/g, '').replace(/\s/g, '');
  return createHash('sha256').update(Buffer.from(b64, 'base64')).digest('hex');
}

const buildProfilePath = join(REPO_ROOT, 'build-profile.json5');
const moduleJsonPath = join(REPO_ROOT, 'entry', 'src', 'main', 'module.json5');
const appJsonPath = join(REPO_ROOT, 'AppScope', 'app.json5');
for (const required of [buildProfilePath, moduleJsonPath, appJsonPath]) {
  if (!existsSync(required)) {
    console.log('RESULT: FAIL\n缺少输入文件：' + required);
    process.exit(2);
  }
}

const buildProfile = readJson5(buildProfilePath);
const configs = (buildProfile.app && buildProfile.app.signingConfigs) || [];
const releaseConfig = configs.find((c) => c.name === 'release');
if (!profileOverride && !releaseConfig) {
  console.log('RESULT: FAIL\nbuild-profile.json5 里没有名为 release 的签名配置，无法判断发布 Profile。');
  process.exit(2);
}

const activeName = buildProfile.app && buildProfile.app.products && buildProfile.app.products[0]
  ? buildProfile.app.products[0].signingConfig : null;

let profilePath = profileOverride;
let certPath = releaseConfig && releaseConfig.material ? releaseConfig.material.certpath : null;
if (profileOverride && !isAbsolute(profileOverride)) profilePath = resolve(REPO_ROOT, profileOverride);
if (!profilePath) {
  profilePath = releaseConfig.material.profile;
  if (!isAbsolute(profilePath)) profilePath = resolve(REPO_ROOT, profilePath);
}
if (!existsSync(profilePath)) {
  console.log('RESULT: FAIL\nProfile 不存在：' + profilePath);
  process.exit(2);
}

let profile;
try {
  profile = decodeProfileJson(readFileSync(profilePath));
} catch (error) {
  console.log('RESULT: FAIL\n解 Profile 失败（' + profilePath + '）：' + error.message);
  process.exit(2);
}

const appJson = readJson5(appJsonPath);
const bundleName = appJson.app.bundleName;
const moduleJson = readJson5(moduleJsonPath);
const requested = ((moduleJson.module && moduleJson.module.requestPermissions) || [])
  .map((p) => (typeof p === 'string' ? p : p.name))
  .filter(Boolean);

const info = profile['bundle-info'] || {};
const allowedAcls = (profile.acls && profile.acls['allowed-acls']) || [];
const certKind = info['distribution-certificate'] ? 'distribution-certificate' : 'development-certificate';
const embeddedPem = info['distribution-certificate'] || info['development-certificate'] || '';

say('Profile : ' + profilePath);
say('  用法      : 当前 products[0].signingConfig = "' + activeName + '"' + (activeName === 'release' ? '' : '  ← 发布包要改成 "release"'));
say('  type      : ' + profile.type + '   (' + profile['app-distribution-type'] + ')');
say('  uuid      : ' + profile.uuid);
say('  bundle    : ' + info['bundle-name']);
say('  appId     : ' + info['app-identifier'] + '   apl=' + info.apl);
say('  证书      : ' + certKind + '  sha256=' + sha256OfPem(embeddedPem).slice(0, 32) + '…');
say('  acls      : ' + (allowedAcls.length === 0 ? '（空）' : JSON.stringify(allowedAcls)));
say('module.json5 requestPermissions: ' + (requested.length === 0 ? '（空）' : JSON.stringify(requested)));

if (profile.type !== 'release') fail('Profile 的 type 是 "' + profile.type + '"，不是 release —— 发布包不能用调试 Profile。');
if (profile['app-distribution-type'] !== 'app_gallery') fail('app-distribution-type 是 "' + profile['app-distribution-type'] + '"，不是 app_gallery。');
if (info['bundle-name'] !== bundleName) fail('Profile 的 bundle-name 是 "' + info['bundle-name'] + '"，与 AppScope/app.json5 的 "' + bundleName + '" 不一致。');
if (certKind !== 'distribution-certificate') fail('Profile 内嵌的是 development-certificate（调试证书），不是发布证书。');

if (certPath) {
  const certFull = isAbsolute(certPath) ? certPath : resolve(REPO_ROOT, certPath);
  if (!existsSync(certFull)) {
    fail('build-profile.json5 里的 material.certpath 不存在：' + certFull);
  } else {
    const profileCertSha = sha256OfPem(embeddedPem);
    const certFileSha = leafCertSha256(readFileSync(certFull, 'utf8'));
    say('  证书绑定  : certpath 叶子 ' + certFileSha.slice(0, 32) + '…  vs  Profile ' + profileCertSha.slice(0, 32) + '…');
    if (profileCertSha !== certFileSha) {
      fail('Profile 内嵌证书与 material.certpath 的叶子证书不是同一份 ⇒ 换证书了，fingerprint 会变，按指纹鉴权的开放能力需在 AGC 重新配指纹。');
    }
  }
}

const allowedSet = new Set(allowedAcls);
for (const name of requested) {
  const inProfile = allowedSet.has(name);
  const restricted = RESTRICTED.has(name);
  say('  权限      : ' + (inProfile ? '[in acls] ' : '[NOT in acls] ') + name + (restricted ? '  (受限权限：必须在 acls 里)' : ''));
  if (restricted && !inProfile) {
    fail('module.json5 请求的受限权限 ' + name + ' 不在 Profile 的 acls.allowed-acls 里 ⇒ AGC 上传会报 "ACL permission consistency"（重新申请/创建 Profile 时勾上「受限ACL权限（HarmonyOS API9及以上）」）。');
  }
  if (!restricted && !inProfile) {
    say('              ↑ 不在 acls 里；若它其实是受限权限，请在 AGC 的 ACL 权限页签确认，并把名字加进本脚本的 RESTRICTED 表。');
  }
}
for (const name of allowedAcls) {
  if (!requested.includes(name)) {
    say('  注意      : Profile 的 acls 里有 ' + name + '，但 module.json5 没请求它（AGC 勾选时会把该应用已获取的 ACL 权限全部写进 Profile，正常情况可忽略）。');
  }
}

if (problems.length === 0) {
  console.log('RESULT: OK —— 这个 Profile 可以打发布包。');
  process.exit(0);
}
console.log('RESULT: FAIL');
for (const p of problems) console.log('  - ' + p);
process.exit(1);
