# scripts/i18n-reference —— i18n 生成链的输入正本

本目录是 i18n 资源生成链的**输入正本**。`scripts/generate-i18n-resources.mjs` 与
`scripts/report-i18n-counts.mjs` 只读这里；**它们不再读工作树里的 `reference/`**。

## 为什么把它们收进版本库

- 这两份字典原来住在**另一个仓库**里：原始 React Native for OpenHarmony 版 learnOH
  （见 `CONTEXT.md`「参考实现」）。那个工程**不属于本仓库**，被 `.gitignore` 整目录忽略，
  只存在于账号所有者这台机器上（形如 `reference/learnOH-old` 的链接）。
  后果：别人克隆本仓库后，`node scripts/generate-i18n-resources.mjs` 读不到输入而失败，
  而 `CONTEXT.md`、几个脚本注释与生成物头部却指向那个不存在的路径 —— 工具链不自足。
- **收进来不新增任何对外暴露面**：这两份字典的内容本来就**逐字**已经进了生成物
  `entry/src/main/resources/{base,zh_CN,en_US}/element/string.json`（186 个 `loh_` 键），
  也就是说这些字节早就在版本库里、早就随应用发布。收进来只是把**构建输入**从
  「别人的工作区」挪进版本库，**产物一个字节都没变**（改动前后的 SHA256 见验收记录）。
- 换来的东西：克隆即可跑生成器；上游工程从构建链上被彻底摘掉；
  「字典长什么样」这件事第一次可以在本仓库里被复核。

## 来源

| 项 | 值 |
| --- | --- |
| 上游工程 | 原始 React Native for OpenHarmony 版 learnOH（不属于本仓库） |
| 取出时所在的开发机路径 | `D:\Koracan\source\harmony\learnOH-old\src\assets\translations` |
| 上游文件 mtime | 2026-03-11 21:36:14 |
| 上游版本标识 | 该工程没有可用的 git 版本号（不是本仓库的 checkout）；下面记的是逐字节指纹 |
| `zh.ts` SHA256 | `7F2F19FD272FFEA14035A5A70CD62FAEA5A9EFFACB713970F23CA554085B6CBC`（10043 字节） |
| `en.ts` SHA256 | `01A227492B51296887A41FA8F080D5E299F89E83FA826CC37394ADA0D6D02721`（10713 字节） |
| 收进本仓库 | 2026-09-15，分支 `wt/t23` |
| 复制方式 | `Copy-Item` 逐字节复制，**未重新排版、未改换行、未格式化** |

复核方式（不依赖上游工程）：用上面的 SHA256 比对本目录的两个文件，
或直接看生成物 —— `entry/src/main/resources/zh_CN/element/string.json` 里 186 个
`loh_` 键的取值就是 `zh.ts` 的取值（`en_US` 对应 `en.ts`）。

## 上游许可

上游 `LICENSE` 是 **MIT**，另加一条只约束「清华计算中心在/曾在职人员及其资助项目」的附加条款。
MIT 正文要求 *"The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software."* —— 这两份 ts 各约 10 KB，属于上游源码的
实质部分，因此**声明原文照录如下**（与上游 `LICENSE` 逐字一致）:

```text
MIT License

Copyright (c) 2026 Han Wong

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

For those who are working or have worked for Computer and Information Managing
Center, Tsinghua University or those whose project is financially supported
by any institute in relation to Tsinghua University: any usage of code, without
explicit authorizations from the author, from this project will be considered
as infringement of copyright. The word "usage" may refer to making copies of,
modifying, redistributing of the source code or any derivative of this project,
for either commercial or non-commercial use.

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## 纪律

- 本目录**只读**：没有任何脚本往里写。改字典 = 改生成物，必须走
  `node scripts/generate-i18n-resources.mjs && node scripts/gen-i18n-keys.mjs`，
  不要手工编辑 `entry/src/main/resources/**/string.json` 或 `I18nKeys.ets`。
- 需要的键**新增/替换**在这两份字典里做；本工程**不要**的键在
  `scripts/i18n-lib.mjs` 的 `RETIRED_REFERENCE_KEYS` 里退休，**不要**从字典里删 ——
  字典保持上游原样，「本工程用到哪些」由 `RETIRED_REFERENCE_KEYS` 表达。
- 这两份文件保持**上游逐字节原样**，便于将来与上游再比对；
  内容一旦需要偏离上游，那就该是一份新文件，而不是改这两个。
