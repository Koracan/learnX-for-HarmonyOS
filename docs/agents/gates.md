# 门禁：提交前必跑，以及"假绿"陷阱

> 由 `AGENTS.md` 指向：**要提交、要判断一次构建/测试是否真的通过时读这里。**

## 四条必跑

1. **先设 `DEVECO_SDK_HOME`**（见 `docs/agents/environment.md` 的「构建」节，不设会一条测试都不跑）。
2. **单测**：**先删 `entry/.test`**，再

       & 'C:/Program Files/Huawei/DevEco Studio/tools/hvigor/bin/hvigorw.bat' --mode module -p module=entry@default -p product=default test --no-incremental

   然后读 **`entry/.test/default/intermediates/test/coverage_data/test_result.txt`** 的 `Tests run:` 行，
   **并核对这个文件的时间戳是本轮的**。
3. **打包**：`assembleHap --no-incremental`（后台作业或重定向到 `.dsh/logs/`）。
4. **四个脚本**：`node scripts/check-domain-purity.mjs` → PASS；`check-import-graph.mjs` → PASS；
   `check-i18n-keys.mjs` → `RESULT: OK`；`check-generated-fresh.mjs` → PASS。

**报告口径**：交付时给出**原始数字**（`Tests run` 那一行、脚本输出），并与上一轮的基线比较。
**不要把基线数字写死进本文件**——它每轮都在变，写死必过时。

## 假绿 / 假红陷阱

### 1. 作业退出码不可信

把命令写成 `cmd *> log; ('EXIT=' + $LASTEXITCODE) | Out-File …` 时，**进程退出码会变成 0**
（最后一条是 `Out-File`）。**必须读日志与产物**，不要读退出码。

### 2. 看到 `BUILD SUCCESSFUL` 也不等于编译成功

实测（ticket 15）：引入一个 ohpm 包做冒烟，日志里先是

    > hvigor ERROR: ErrorCode: 00507015 … does not provide an export name …
    > hvigor BUILD SUCCESSFUL in 25 s 262 ms

**ERROR 之后紧跟着 BUILD SUCCESSFUL** ⇒ 判编译成败必须搜 `ERROR` / `ErrorCode` / `COMPILE RESULT`，
**不能只看最后一行**。与陷阱 1 是同一族：工具的成功信号比它看起来的弱。

### 3. `hvigorw test` 退出码 0 / BUILD SUCCESSFUL 也可能是"没跑"或"陈旧产物"

- **测试没跑**：几秒就返回、日志里没有 `Tests run` ⇒ 命中了 up-to-date 缓存。
  修法见上（先删 `entry/.test` + `--no-incremental`）。
- **产物陈旧**（ticket 07 实测）：探针用完后把模块删掉，增量构建仍返回成功、**产物时间戳不变**，
  而 hap 里的 `ets/modules.abc` **仍引用已删除的模块**，装机启动即 `ReferenceError`。判定与修法：
  1. **时间戳不变 = 没重新构建** —— 必要条件但不充分；
  2. 还要**内容级检查**：把 hap 当 zip 解开（`Copy-Item x.hap x.zip; Expand-Archive x.zip out`），
     在解出来的 `ets/modules.abc` 里搜「应当消失的符号」与「应当存在的符号」。
     **不要直接对 `.hap` 做字节检索**——zip 条目是压缩的，搜不到不等于没有，会给出**假阴性**；
  3. 不确定时**删 `entry/build` 全量重建**，装机后确认应用日志里启动正常（`ReferenceError` 只在运行时炸）。

**推论（很重要）**：「我把开关翻回 false / 把探针删了，并重新构建过」**不是证据**。
取证态 → 提交态的转变必须给出**产物级或视觉级**证据（产物内容检索，或一张提交态界面截图），否则可能验的是上一个产物。

### 4. `check-generated-fresh` 在**全新 checkout / 新 worktree 里第一次跑必红**（假红，已于 2026-09-13 从根上修掉）

生成器按 **LF** 写出那 6 个生成物，而仓库原先没有 `.gitattributes` + 本机 `core.autocrlf=true`
⇒ checkout 把它们落成 CRLF ⇒ 脚本「跑前 / 跑后 sha256」必然不等。现象：**首次跑 `FAIL` 并就地重生，重跑即 PASS**，
而 `git diff` 对这 6 个路径是空的（内容其实一致）。新 worktree 缺 `reference/` 会让 i18n 两个脚本更早变红，别与这条混淆。

**已修**：仓库根的 `.gitattributes` 把这 6 个路径固定成 `text eol=lf`。若在新克隆上又见到这条假红，
先自查属性是否生效（期望 `text: set` / `eol: lf`）：

    git check-attr text eol -- entry/src/main/resources/zh_CN/element/string.json

**判据仍是**：`git diff` 对这 6 个生成物为空 ⇒ 内容一致 ⇒ 假红。别把「重跑一次就绿」变成习惯动作。

## 两个脚本守住的不变量

### `check-import-graph.mjs`：按入口可达性编译

**ArkTS 的编译按入口可达性进行**：没有任何可达者 import 的模块**不会被编译**，其中的硬错误（含无法解析的 import）不会让任何门禁变红。
实测：`data/upload/UploadForm.ets` 从 ticket 05 起就 import 了一个不存在的模块，而该 ticket 的构建与 116 条单测**全绿**，
直到 ticket 06 第一次 import 它才暴露。

⇒ **新交付的模块必须至少被一条可达路径（应用入口或某个测试）import**，否则它的"编译通过"从未被验证。
该脚本 FAIL 掉不可解析的相对 import，并 WARN 列出**孤儿模块**（没有任何可达者 import 的 main 源文件）。
**入口文件出现在该列表属正常；其余任何文件出现在那里，就意味着它从未被编译过。**

### `check-generated-fresh.mjs`：生成物与生成器输入一致

**要守的不变量**：在任何一次提交上，**重跑生成器后 `git diff` 必须为空**。
该脚本就是它的可操作形式：对 6 个 i18n 生成物取哈希 → 重跑两个生成器 → 再取哈希，**变了就 FAIL 并已就地重生**。

**两个 agent 不要同时改 i18n 生成器的输入**（`generate-i18n-resources.mjs` / `i18n-ui-strings.mjs`）。
若不可避免：**后提交者负责重跑生成器**；先提交者若带上对方的输入，必须在**提交信息里写明归因**。

安全方向是明确的：**键已声明但没人用 = 无害；有人用但键没声明 = 编译错误**（`I18nKeys.ets` 是类型化联合），
所以"先把键声明带上"可以接受。