// check-glyphs.mjs — ticket 11.5 复核：参考实现用到的图标名 → 族 → 码位 → 字形是否真的在字体里
// 用 node 跑：node .scratch/icons/evidence/check-glyphs.mjs
// 数据源（只读）：reference/learnOH-old/node_modules/react-native-vector-icons/
//   glyphmaps/MaterialCommunityIcons.json、glyphmaps/MaterialIcons.json、Fonts/*.ttf
import fs from 'node:fs';
import path from 'node:path';

const RVI = 'reference/learnOH-old/node_modules/react-native-vector-icons';
const mciMap = JSON.parse(fs.readFileSync(path.join(RVI, 'glyphmaps/MaterialCommunityIcons.json'), 'utf8'));
const miMap = JSON.parse(fs.readFileSync(path.join(RVI, 'glyphmaps/MaterialIcons.json'), 'utf8'));

/** 解析 TTF 的 cmap，返回"有字形"的码位集合（format 4 + format 12）。 */
function cmapOf(file) {
  const buf = fs.readFileSync(file);
  const numTables = buf.readUInt16BE(4);
  let cmapOff = -1;
  for (let i = 0; i < numTables; i++) {
    const off = 12 + i * 16;
    if (buf.toString('ascii', off, off + 4) === 'cmap') cmapOff = buf.readUInt32BE(off + 8);
  }
  if (cmapOff < 0) throw new Error('no cmap in ' + file);
  const n = buf.readUInt16BE(cmapOff + 2);
  const cps = new Set();
  for (let i = 0; i < n; i++) {
    const subOff = cmapOff + buf.readUInt32BE(cmapOff + 4 + i * 8 + 4);
    const format = buf.readUInt16BE(subOff);
    if (format === 4) {
      const segCount = buf.readUInt16BE(subOff + 6) / 2;
      const endOff = subOff + 14;
      const startOff = endOff + segCount * 2 + 2;
      const deltaOff = startOff + segCount * 2;
      const rangeOff = deltaOff + segCount * 2;
      for (let s = 0; s < segCount; s++) {
        const end = buf.readUInt16BE(endOff + s * 2);
        const start = buf.readUInt16BE(startOff + s * 2);
        const delta = buf.readInt16BE(deltaOff + s * 2);
        const rangeOffset = buf.readUInt16BE(rangeOff + s * 2);
        if (end === 0xFFFF) continue;
        for (let c = start; c <= end && c !== 0x10000; c++) {
          let gid;
          if (rangeOffset === 0) {
            gid = (c + delta) & 0xFFFF;
          } else {
            const giOff = rangeOff + s * 2 + rangeOffset + (c - start) * 2;
            if (giOff + 1 >= buf.length) continue;
            gid = buf.readUInt16BE(giOff);
            if (gid !== 0) gid = (gid + delta) & 0xFFFF;
          }
          if (gid !== 0) cps.add(c);
        }
      }
    } else if (format === 12) {
      const groups = buf.readUInt32BE(subOff + 12);
      for (let g = 0; g < groups; g++) {
        const go = subOff + 16 + g * 12;
        const start = buf.readUInt32BE(go);
        const end = buf.readUInt32BE(go + 4);
        const startGid = buf.readUInt32BE(go + 8);
        if (startGid === 0) continue;
        for (let c = start; c <= end; c++) cps.add(c);
      }
    }
  }
  return cps;
}

const mciCmap = cmapOf(path.join(RVI, 'Fonts/MaterialCommunityIcons.ttf'));
const miCmap = cmapOf(path.join(RVI, 'Fonts/MaterialIcons.ttf'));
const hex = (v) => '0x' + v.toString(16).toUpperCase();

console.log('JSON 名数: MCI=' + Object.keys(mciMap).length + '  MI=' + Object.keys(miMap).length);
console.log('cmap 码位数: MCI=' + mciCmap.size + '  MI=' + miCmap.size);
console.log('');

// 参考实现各调用点实际用的族（已逐处读源码确认，见 ticket 11.5 交付 §1 的出处列）
const USED = [
  // [参考图标名, 参考用的族, 参考出处]
  ['attachment', 'MCI', 'NoticeCard.tsx:49 AssignmentCard.tsx:55 AssignmentDetail.tsx:198'],
  ['flag', 'MCI', 'NoticeCard.tsx:57 FileCard.tsx:50'],
  ['checkbox-blank-circle', 'MCI', 'NoticeCard.tsx:65 FileCard.tsx:58'],
  ['check', 'MCI', 'AssignmentCard.tsx:63 AssignmentDetail.tsx:217 Filter.tsx:85'],
  ['key-variant', 'MCI', 'AssignmentCard.tsx:79 AssignmentDetail.tsx:304'],
  ['medal', 'MCI', 'AssignmentCard.tsx:87 AssignmentDetail.tsx:340'],
  ['notifications', 'MI', 'App.tsx:619 CourseCard.tsx:37'],
  ['event', 'MI', 'App.tsx:620 CourseCard.tsx:41'],
  ['folder', 'MI', 'App.tsx:621 CourseCard.tsx:47'],
  ['apps', 'MI', 'App.tsx:622'],
  ['settings', 'MI', 'App.tsx:623'],
  ['grade', 'MI', 'AssignmentCard.tsx:71 AssignmentDetail.tsx:258'],
  ['insert-drive-file', 'MI', 'NoticeDetail.tsx:102 FileDetail.tsx:220'],
  ['check-circle', 'MI', 'Empty.tsx:15'],
  ['arrow-back', 'MI', '导航栈默认返回箭头（截图里就是它）'],
  ['close', 'MI', 'App.tsx:113（BackButton）'],
  ['search', 'MI', 'App.tsx:154'],
  ['filter-list', 'MI', 'FilterList.tsx:188'],
  ['visibility', 'MI', 'CardWrapper.tsx:75'],
  ['visibility-off', 'MI', 'CardWrapper.tsx:75 Filter.tsx:77'],
  ['file-upload', 'MI', 'AssignmentDetail.tsx:111'],
  ['error', 'MI', 'FileDetail.tsx:160'],
  ['keyboard-arrow-right', 'MI', 'TableCell.tsx:116'],
  ['file-download', 'MI', 'FileDetail.tsx:232'],
  ['person-remove', 'MI', 'Settings.tsx:69'],
  ['loop', 'MI', 'Settings.tsx:85'],
  ['rule-folder', 'MI', 'Settings.tsx:91'],
  ['policy', 'MI', 'Settings.tsx:98'],
  ['help', 'MI', 'Settings.tsx:108'],
  ['copyright', 'MI', 'Settings.tsx:114'],
  ['cached', 'MI', 'FileSettings.tsx:58（TableCell 用 MaterialIcons 渲染）'],
  ['drive-file-rename-outline', 'MI', 'FileSettings.tsx:77'],
  ['delete', 'MI', 'FileSettings.tsx:96'],
  ['fullscreen', 'MI', 'Settings.tsx:77 ImmersiveSettings.tsx:35 TableCell 渲染'],
  ['center-focus-strong', 'MI', 'ImmersiveSettings.tsx:44'],
  ['preview', 'MI', 'FileDetail.tsx:130'],
  ['info-outline', 'MI', 'FileDetail.tsx:130'],
  ['account', 'MCI', 'TableCell.tsx:75（Avatar.Icon → paper 默认族 MCI）'],
  ['heart', 'MCI', 'Filter.tsx:73 CardWrapper.tsx:94'],
  ['heart-off', 'MCI', 'CardWrapper.tsx:94'],
  ['archive-arrow-up', 'MCI', 'CardWrapper.tsx:111'],
  ['archive-arrow-down', 'MCI', 'CardWrapper.tsx:111'],
  ['open-in-new', 'MCI', 'FileDetail.tsx:123（IconButton → paper 默认族 MCI）'],
  ['refresh', 'MCI', 'FileDetail.tsx:114'],
  ['share', 'MCI', 'FileDetail.tsx:118'],
  ['fullscreen-exit', 'MCI', 'FileDetail.tsx:111'],
  ['inbox', 'MCI', 'Filter.tsx:68'],
  ['email-mark-as-unread', 'MCI', 'Filter.tsx:71'],
  ['archive', 'MCI', 'Filter.tsx:75'],
  ['checkbox-blank-circle-outline', 'MCI', 'Filter.tsx:79'],
  ['checkbox-marked-circle-outline', 'MCI', 'Filter.tsx:80']
];

let jsonMiss = 0, cmapMiss = 0;
for (const [name, family, src] of USED) {
  const map = family === 'MCI' ? mciMap : miMap;
  const cmap = family === 'MCI' ? mciCmap : miCmap;
  const cp = map[name];
  const inJson = typeof cp === 'number';
  const inCmap = inJson && cmap.has(cp);
  if (!inJson) jsonMiss++;
  if (inJson && !inCmap) cmapMiss++;
  console.log([name.padEnd(30), family.padEnd(4), (inJson ? hex(cp) : 'JSON-MISSING').padEnd(14), 'inFont=' + inCmap, ' <- ' + src].join(' '));
}
console.log('');
console.log('汇总: 参考实际用到的 ' + USED.length + ' 个名字里，JSON 缺 ' + jsonMiss + ' 个；JSON 有但字体 cmap 无字形 ' + cmapMiss + ' 个');

// 明确不是图标名的两条（FilterListItem 的 name prop / meta viewport）
console.log('');
for (const n of ['all', 'archived', 'fav', 'finished', 'hidden', 'unfinished', 'unread', 'viewport']) {
  console.log('非图标名核对: ' + n.padEnd(12) + ' MCI-JSON=' + (mciMap[n] === undefined ? 'absent' : hex(mciMap[n]))
    + ' MI-JSON=' + (miMap[n] === undefined ? 'absent' : hex(miMap[n])));
}
