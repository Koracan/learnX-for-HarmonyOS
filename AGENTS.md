# AGENTS.md

## 项目

learnOH —— HarmonyOS 原生（ArkTS / ArkUI）应用，是原 React Native for OpenHarmony 实现的重写。

 - 原始 RN 工程在 `reference/learnOH-old/`，作移植参考。

## 注意

 - 多设备时必须显式传 `--device`。当前目标设备是**模拟器** `Pura 90`（电话形态，HarmonyOS 6.1.0(23)，串口 `127.0.0.1:5555`；未启动则 `devecocli emulator start "Pura 90"`）。真机 `3FYBB25407201890`（HUAWEI MatePad Air，API 24）暂未连接。先用 `devecocli device list` 解析出确切串口再传。

 - `devecocli run` 必须作为后台作业运行。 它在应用启动后仍保持运行，直到应用退出才返回——前台调用会一直挂住。

 - 构建耗时以分钟计，不要用会阻塞的短超时前台调用：把输出重定向到 `.dsh/logs/`，或作为后台作业运行。用管道（`| Select-Object`）转发 devecocli 的 stdout 会丢失 hvigor 的失败信息并让命令迟迟不返回。

 - 签名问题参见 `docs\sign.md`。

 - **验收证据口径**：日常验收在模拟器 `Pura 90` 上取证即可（串口 `127.0.0.1:5555`，HarmonyOS **6.1.0(23)**，与工程声明的 `compatibleSdkVersion` 同版本）。截图与日志按实标注来源为"模拟器"，**不要写成"真机"**。真机 `3FYBB25407201890`（MatePad Air，**API 24**）只做**最终一次性复验**，时点卡在 ticket 18（发布收尾）之前，用于覆盖"更高 API 上的向后兼容"这一层——见 `spec.md` 第 8 节。

## 并发资源（多 agent 同仓时必须遵守）

 - **构建产物与模拟器都是单例资源**，同一时刻只允许一个 agent 占用。两个 agent 同时跑 `devecocli build` 会互相覆盖 `entry/build/default/outputs/default/entry-default-signed.hap`——后者的产物会让前者已装的 app 与源码对不上；两个 agent 同时操作同一台模拟器会让 `hdc install`/点击/截图互相踩踏（已实测：一次 install 卡死 11 分钟，产物于 02:32:35 被另一 agent 的构建覆盖）。

 - **按资源类型分工，而不是让所有人排队**：要产 hap、要装设备、要点 UI、要截图、要取 log 的 agent **独占设备**；只跑 `hvigorw test` 与改代码的 agent **不需要设备**（`hvigorw test` 写 `entry/.test` 与 build 中间产物，不产 signed hap，不影响设备上已安装的 app）。让这两类工作并行。

 - **需要独占时向统筹者申请窗口**，不要在共享资源上自行重试或抢占；拿到窗口的 agent 在收尾时明确回报"窗口关闭"。

 - **取证必须可追溯到源码版本**：截图与日志要记下当时的 `git rev-parse HEAD`；若工作区是脏的，同时记下 `git status --porcelain` 的哈希。取证期间工作区被他人改动，该取证就不再对应任何提交，只能作为过程证据。

## 移植时的硬约束

 - **改参考实现的"怪癖"之前，先读 `docs/reference-quirks.md`**。那里登记的是`reference/learnOH-old/` 里**看起来像 bug、实为有意行为或能力缺口补丁**的点（下载补丁、重登触发条件、学期排序、正则不解码实体、CJK 搜索合并层），每条带源文件行号与"为什么别急着改"。**移植的完成定义是与参考实现行为一致**——顺手"修好"它会让行为偏离，并让验收失去可比对的基准。
 - 要偏离某一条时：**先改那张表的状态并写明替代验收标准**，再改代码。只改代码不改表，等于隐式推翻决策。

## Agent skills

### 问题跟踪

本仓库的 issue 和 spec 以 Markdown 文件形式存放在 `.scratch/<feature-slug>/` 下。参见 `docs/agents/issue-tracker.md`。

### 领域文档

单上下文（single-context）：仓库根目录一份 `CONTEXT.md`，外加 `docs/adr/`。参见 `docs/agents/domain.md`。
