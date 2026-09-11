# AGENTS.md

## 项目

learnOH —— HarmonyOS 原生（ArkTS / ArkUI）应用，是原 React Native for OpenHarmony 实现的重写。

 - 原始 RN 工程在 `reference/learnOH-old/`，作移植参考。

## 注意

 - 多设备时必须显式传 `--device`；当前唯一真机是 `3FYBB25407201890`（HUAWEI MatePad Air，API 24）。

 - `devecocli run` 必须作为后台作业运行。 它在应用启动后仍保持运行，直到应用退出才返回——前台调用会一直挂住。

 - 构建耗时以分钟计，不要用会阻塞的短超时前台调用：把输出重定向到 `.dsh/logs/`，或作为后台作业运行。用管道（`| Select-Object`）转发 devecocli 的 stdout 会丢失 hvigor 的失败信息并让命令迟迟不返回。

 - 签名问题参见 `docs\sign.md`。

## Agent skills

### 问题跟踪

本仓库的 issue 和 spec 以 Markdown 文件形式存放在 `.scratch/<feature-slug>/` 下。参见 `docs/agents/issue-tracker.md`。

### 领域文档

单上下文（single-context）：仓库根目录一份 `CONTEXT.md`，外加 `docs/adr/`。参见 `docs/agents/domain.md`。
