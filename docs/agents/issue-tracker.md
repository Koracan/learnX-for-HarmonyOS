# 问题跟踪：本地 Markdown

本仓库的 issue 和 spec 以 Markdown 文件的形式存放在 `.scratch/` 下。

## 约定

- 一个功能一个目录：`.scratch/<feature-slug>/`
- spec 位于 `.scratch/<feature-slug>/spec.md`
- 实现类 issue 一个 ticket 一个文件，位于 `.scratch/<feature-slug>/issues/<NN>-<slug>.md`，从 `01` 开始编号，绝不写成单个合并的 tickets 文件
- 每个 issue 文件顶部附近用一行 `Status:` 记录分诊状态
- 评论与讨论历史追加到文件末尾的 `## Comments` 标题之下

## 当某个 skill 说"发布到 issue tracker"

在 `.scratch/<feature-slug>/` 下新建一个文件（目录不存在则先创建）。

## 当某个 skill 说"取出相关 ticket"

读取对应路径的文件。通常由用户直接给出路径或 issue 编号。
