# 模糊搜索包评估（事实）

评估日期：2026-09-11。方法：ohpm registry openapi search/detail + **下载并解包 .har** 验证是否为纯 ArkTS。
工程现状：根/entry `oh-package.json5` 目前**无任何依赖**（fuse.js 只存在于旧 RN 工程）。

| 包 | 最新 | 发布 | 许可 | 发布者 | 下载/points | HAR 体积 | 纯 ArkTS（无 NAPI）？ | 说明 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **@ohos/flexsearch** | 2.0.1 | 2025-04-14 | Apache-2.0 | xiatian (OH TPC) | 492 / 25 | **38 KB** | ✅ ESM `.js` + d.ts，0 依赖，无 .so/.node | flexsearch 0.7.2 移植，`main: ./src/flexsearch.js`；文档支持 `charset:"cjk"` 与多字段 Document 索引。**风险：返回分字段结果，无跨字段加权总分** |
| @isrc/fuse.js | 1.0.1 | **2023-09-28** | Apache-2.0 | Cao Tianheng | 901 / 25 | **5.6 MB** | ✅ | fuse v6 移植；`entry.js` 自造 `globalThis.process` shim；`Fuse.version` 仍是 `'__VERSION__'`；**近 3 年未维护**，体积大半是 demo + gif |
| fastest-levenshtein | 1.1.0 | 2024-11-22 | MIT | ArkAdapter | 644 / 50 | 4.4 KB | ✅ 真实 `.ets` 源码 | 导出 `distance`/`closest`；可作手写评分器的编辑距离内核 |
| wuzzy | 0.0.1 | 2026-07-26 | MIT | ArkAdapter | 3 / 50 | 12 KB | ✅（编译产物） | **字节码 HAR + 混淆，无可读源码**；jarowinkler/levenshtein/ngram/jaccard… |
| dice-string-comparison | 0.0.1 | 2026-07-31 | MIT | ArkAdapter | 3 / 50 | 9.4 KB | ✅（编译） | 同上，混淆字节码 |
| string-similarity | 0.0.1 | 2026-07-26 | MIT | ArkAdapter | 3 / 50 | 5.6 KB | ✅（编译） | 同上 |
| leven-arkts | 1.1.0 | 2024-11-25 | MIT | ArkAdapter | 427 / 50 | 4.1 KB | ✅ | 仅 Levenshtein |
| @ohos/pinyin4js | 2.0.2 | 2025-06-05 | MIT | xiatian (TPC) | **24300** / 25 | 137 KB | ✅ | 中文→拼音，下载量最高 |
| @nutpi/pinyin | 1.0.3 | 2025-01-06 | MIT | 坚果 | 3204 / 50 | 29 KB | ✅ 零依赖 ArkTS | 拼音 |
| @pavilion-stone-walkway/diff-match-patch | 1.0.0 | 2026-09-08 | Apache-2.0 | xlleng | 0 / 25 | 44 KB | ✅ | ⚠️ `compatibleSdkVersion: 26.0.0`，对 API 23 目标**可能无法解析** |
| pinyin-pro | 3.26.0 | 2025-05-14 | MIT | npm | 4564 | 310 KB | ⚠️ `packageType: WHITELIST` | 不是可安装的 ohpm HAR |
| @ohos-rs/pinyin | 0.0.4 | 2024-08-26 | MIT | richerfu | 1627 / 30 | 10.7 MB | ❌ **NAPI/Rust** | 不可用 |
| @ohos-rs/jieba | 0.0.5 | 2024-08-26 | MIT | richerfu | 1224 / 25 | 16.6 MB | ❌ NAPI/Rust | 不可用 |
| @devzeng/tokenizer | 0.1.0 | 2025-03-14 | MIT | zengjing | 138 / 50 | 5.5 MB | ❌ cppjieba 原生 | 不可用 |
| sqlite3-simple | 1.0.0 | 2025-02-25 | Apache-2.0 | SageMik | 234 / 50 | 5.1 MB | ❌ 原生 FTS5 | 不可用 |
| simple-native-ohos | 2.3.0 | 2026-08-08 | Apache-2.0 | SageMik | 505 / 30 | 1.2 MB | ❌ 原生 | 不可用 |
| bert-chinese-tokenizer | 1.0.0 | 2025-08-14 | Apache-2.0 | dfdu233 | 80 / 25 | 72 KB | 不明确 | 方向不符 |

ohpm 上 `fuzzysearch`/`lunr`/`minisearch`/`elasticlunr`/`tantivy`/`全文检索`/`模糊搜索`/`中文分词` **零结果**；不存在 MiniSearch/Lunr 移植。

## 一方 API 里没有可用的模糊匹配

- `Intl.Collator`（`@ohos.intl`，API 8+）：只有 `compare(a,b)` 与 `resolvedOptions().collation`（含 `big5han` 拼音排序）——**只负责排序，无评分/子串/近似匹配**。
- `i18n.BreakIterator`：只暴露 `getLineInstance(locale)`（换行点），**没有 `getWordInstance`**，即没有一方中文分词。
- `@ohos.util`：只有 TextEncoder/Decoder、RationalNumber、Base64、Scope；`@arkts.collections` 只有容器。
- `ohos.data.search`（融合搜索）只有 **Java** 系统 API，未暴露给 ArkTS。
- 可用的只有 ECMAScript 原生：`String.indexOf/normalize`、`RegExp`、`charCodeAt`。

## 结论与理由

1. **首选 `@ohos/flexsearch`**：官方 TPC 移植、Apache-2.0、38 KB、零依赖、无原生码、2025-04 维护、文档明确支持 CJK 与多字段索引。**待验证**：`main: ./src/flexsearch.js` 这种 `.js` 入口能否在 API 23 工程中成功导入（未跑 smoke build）。**需自写**跨字段加权（它返回分字段结果集）。
2. **不用 `@isrc/fuse.js`**：近 3 年未维护、5.6 MB、`Fuse.version` 未替换，且是 fuse v6 移植——迁移过去很可能**原样重现旧版"漏掉明显匹配"的现象**。
3. **CJK 关键事实（决定设计）**：fuse 的 Bitap 对 CJK **按码点逐字**切分，"模糊"只到单字级，匹配不了拼音/同音字；flexsearch 的 `cjk` charset 同样先剥 ASCII 再逐字切分。因此旧版 `hooks/useSearch.ts` 里的**手工精确匹配合并是 CJK 语料下的必要行为，不是 bug 的权宜之计**，移植时必须保留。若要支持拼音检索，需**独立拼音索引字段**（`@ohos/pinyin4js` / `@nutpi/pinyin`），而不是换模糊库。
4. 兜底方案：`fastest-levenshtein`（4.4 KB，真实可读 `.ets` 源码，MIT）作编辑距离内核 + 自写加权评分，可完全避开混淆字节码与失维护移植。
5. 视为不可用：`@ohos-rs/pinyin`、`@ohos-rs/jieba`、`@devzeng/tokenizer`、`sqlite3-simple`、`simple-native-ohos`（全为原生）；`pinyin-pro`（npm 白名单项）；`wuzzy`/`dice-string-comparison`/`string-similarity`（**混淆字节码，无可读源码**）。
