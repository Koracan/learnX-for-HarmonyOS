# 门禁：提交前必跑，以及"假绿"陷阱

> 由 `AGENTS.md` 指向：**要提交、要判断一次构建/测试是否真的通过时读这里。**

## 四条必跑

1. **先设 `DEVECO_SDK_HOME`**（见 `docs/agents/environment.md` 的「构建」节，不设会一条测试都不跑）。
2. **单测**：**先删 `entry/.test`**，再

       & 'C:/Program Files/Huawei/DevEco Studio/tools/hvigor/bin/hvigorw.bat' --mode module -p module=entry@default -p product=default test --no-incremental

   然后读 **`entry/.test/default/intermediates/test/coverage_data/test_result.txt`** 的 `Tests run:` 行，
   **并核对这个文件的时间戳是本轮的**。
3. **打包**：`assembleHap --no-incremental`（后台作业或重定向到 `.dsh/logs/`）。
4. **两个脚本**：`node scripts/check-domain-purity.mjs` → PASS；`check-import-graph.mjs` → PASS；

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

**推论（很重要）**：「我把开关翻回 false / 把探针删了，并重新构建过」**不是证据**。
取证态 → 提交态的转变必须给出**产物级或视觉级**证据（产物内容检索，或一张提交态界面截图），否则可能验的是上一个产物。

### 4. 产物指纹（解包后 `ets/modules.abc` 的 SHA256）**只在同一棵树内可比**（2026-09-13 实测）

同一份源码在**两棵不同的 worktree** 里编译，`ets/modules.abc` **大小完全相同（1783796 B）却字节不同**：
逐字节比较 **350 字节不同**（偏移 8–11 落在 abc 头部，其余成对出现在约 167k–169k 一段）。
- **同一棵树内是确定的**：主树连编三次都得到同一个哈希；`wt/t11` 那棵连编两次也都得到它自己的哈希。

- **但 hap 文件本身的 SHA256 不具可复现性，不能当「产物指纹」用**（2026-09-13 终验实测）：同一棵树、同一份代码连编三次

### `check-import-graph.mjs`：按入口可达性编译

**ArkTS 的编译按入口可达性进行**：没有任何可达者 import 的模块**不会被编译**，其中的硬错误（含无法解析的 import）不会让任何门禁变红。
实测：`data/upload/UploadForm.ets` 从 ticket 05 起就 import 了一个不存在的模块，而该 ticket 的构建与 116 条单测**全绿**，
直到 ticket 06 第一次 import 它才暴露。

⇒ **新交付的模块必须至少被一条可达路径（应用入口或某个测试）import**，否则它的"编译通过"从未被验证。
该脚本 FAIL 掉不可解析的相对 import，并 WARN 列出**孤儿模块**（没有任何可达者 import 的 main 源文件）。
**入口文件出现在该列表属正常；其余任何文件出现在那里，就意味着它从未被编译过。**
