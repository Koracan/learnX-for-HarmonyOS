# AGENTS.md

learnOH —— HarmonyOS 原生（ArkTS / ArkUI）应用，是原 React Native for OpenHarmony 实现的重写。
参考实现在 `reference/learnOH-old/`（**只读**）。

本文件只做**路由**。具体内容都在下列文件里——**按"何时读"那一列触发自己去读**，不要凭印象做。

| 何时读 | 读哪份 |
| --- | --- |
| 要**构建**、装机、跑设备命令，或需要知道有哪些模拟器 / 真机 | `docs/agents/environment.md` |
| 要**提交**，或要判断一次构建 / 测试是否**真的**通过（"假绿"陷阱都在这） | `docs/agents/gates.md` |
| 要与别的 agent **并行**、要拿构建锁或设备锁、要开 worktree、或你的改动可能影响别人已验收的证据 | `docs/agents/concurrency.md` |
| 要**截图 / 拉日志 / 写证据**，或要下"这个现象存在 / 不存在"的结论 | `docs/agents/evidence.md` |
| 要**改动参考实现的行为**（完成定义 = 与它行为一致），或要读 / 改两份台账 | `docs/agents/porting.md` |
| 要开或更新 **issue / spec**（`.scratch/` 下的 Markdown） | `docs/agents/issue-tracker.md` |
| 要动**领域模型**或写 **ADR**（单上下文：`CONTEXT.md` + `docs/adr/`） | `docs/agents/domain.md` |
| 要查**签名**材料与配置 | `docs/sign.md` |
| 要核对当前**进度 / 未闭合项**（各 ticket 的状态与证据表） | `.scratch/migration/issues/` |