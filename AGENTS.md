# AGENTS.md

learnOH —— HarmonyOS 原生（ArkTS / ArkUI）应用，是原 React Native for OpenHarmony 实现的重写。

 - 原始 RN 参考实现在 `reference/learnOH-old/`。

## 注意事项

| 场景 | 文件 |
| --- | --- |
| 构建、装机、跑设备命令，或需要知道有哪些模拟器 / 真机 | `docs/agents/environment.md` |
| 提交，或要判断一次构建 / 测试是否**真的**通过（"假绿"陷阱都在这） | `docs/agents/gates.md` |
| 与别的 agent 并行、要拿构建锁或设备锁、要开 worktree、或你的改动可能影响别人已验收的证据 | `docs/agents/concurrency.md` |
| 截图 / 拉日志 / 写证据，或要下"这个现象存在 / 不存在"的结论 | `docs/agents/evidence.md` |
| 要读 / 改两份台账，或判断"这算不算偏离"（注意：**参考实现只是标尺，不是完成定义**） | `docs/agents/porting.md` |
| 开或更新 issue / spec（`.scratch/` 下的 Markdown） | `docs/agents/issue-tracker.md` |
| 动领域模型或写 ADR（单上下文：`CONTEXT.md` + `docs/adr/`） | `docs/agents/domain.md` |
| 查签名材料与配置 | `docs/sign.md` |
| 核对当前进度 / 未闭合项（各 ticket 的状态与证据表） | `.scratch/migration/issues/` |
