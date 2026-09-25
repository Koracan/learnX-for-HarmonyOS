# AGENTS.md

learnOH —— HarmonyOS 原生网络学堂应用。

## 登录

- 可使用 Mock 账户，账户名和密码均为 guest.
- 如需使用真实账户，需要请用户辅助。

## 注意事项

| 场景 | 文件 |
| --- | --- |
| 构建、装机、跑设备命令，或需要知道有哪些模拟器 / 真机 | `docs/agents/environment.md` |
| 提交，或要判断一次构建 / 测试是否**真的**通过（"假绿"陷阱都在这） | `docs/agents/gates.md` |
| 与别的 agent 并行、要拿构建锁或设备锁、或你的改动可能影响别人已验收的证据 | `docs/agents/concurrency.md` |
| 要派单 / 要开 worktree 或配设备 / 要处置串树 | `docs/agents/orchestrating.md` |
| 截图 / 拉日志 / 写证据，或要下"这个现象存在 / 不存在"的结论 | `docs/agents/evidence.md` |
| 开或更新 issue / spec（`.scratch/` 下的 Markdown） | `docs/agents/issue-tracker.md` |
| 动领域模型或写 ADR（单上下文：`CONTEXT.md` + `docs/adr/`） | `docs/agents/domain.md` |
| 用户明确提到签名问题（发布包 / p7b / ACL / 证书 / 上架）时 | `docs/sign.md` |
