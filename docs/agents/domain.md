# 领域文档

工程类 skill 在探索本仓库代码时，应如何消费本仓库的领域文档。

## 探索之前，先读这些

- 仓库根目录的 **`CONTEXT.md`**；或者
- 若根目录存在 **`CONTEXT-MAP.md`**：它指向每个上下文各自的 `CONTEXT.md`，把与你当前主题相关的每一份都读一遍。
- **`docs/adr/`**：读取与你要动手的区域相关的 ADR。在多上下文仓库中，还要检查 `src/<context>/docs/adr/` 里上下文范围内的决策。

如果这些文件不存在，**静默继续**。不要指出它们缺失，也不要主动建议先把它们建起来。`/domain-modeling` skill（经由 `/grill-with-docs` 与 `/improve-codebase-architecture` 触达）会在术语或决策真正被确定下来时按需创建。

## 文件结构

单上下文仓库（大多数仓库）：

```
/
├── CONTEXT.md
├── docs/adr/
│   ├── 0001-event-sourced-orders.md
│   └── 0002-postgres-for-write-model.md
└── src/
```

多上下文仓库（根目录存在 `CONTEXT-MAP.md`）：

```
/
├── CONTEXT-MAP.md
├── docs/adr/                          ← 系统级决策
└── src/
    ├── ordering/
    │   ├── CONTEXT.md
    │   └── docs/adr/                  ← 上下文专属决策
    └── billing/
        ├── CONTEXT.md
        └── docs/adr/
```

## 使用术语表里的词汇

当你的产出提到某个领域概念时（无论是 issue 标题、重构提案、假设还是测试名），请使用 `CONTEXT.md` 中定义的术语。不要漂移到术语表明确回避的同义词上。

如果你需要的概念还不在术语表里，这是一个信号：要么你在发明项目并不使用的说法（重新考虑），要么这里存在真实的空缺（记下来交给 `/domain-modeling`）。

## 标出 ADR 冲突

如果你的产出与既有 ADR 相矛盾，请显式指出，而不是悄悄覆盖：

> _与 ADR-0007（事件溯源订单）相矛盾，但值得重新讨论，因为……_
