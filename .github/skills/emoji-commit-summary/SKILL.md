---
name: emoji-commit-summary
description: 'Analyze staged git changes and write a concise emoji commit summary using the git-commit-emoji-cn mapping. Use when asked to summarize staged changes, draft a gitmoji commit message, or convert a diff into emoji-prefixed work items with a 50-character limit.'
argument-hint: '可选：指定只分析暂存区或工作区改动'
---

# Emoji Commit Summary

Read the staged diff, group it into work items, and write each item as
`<emoji> <type>: 中文摘要`, combining
[git-commit-emoji-cn](https://github.com/liuchengxu/git-commit-emoji-cn) with
Conventional Commits types. Keep the whole summary within 50 Chinese characters.

Use the **actual emoji character** (🐛 📖 🆕 …), never the `:bug:` shortcode: chat UIs do
not render shortcodes, so they show up as plain text.

## When to Use

- "分析暂存区改动并总结"
- "用 emoji 写提交信息"
- "把这次 diff 归纳成几条工作项"
- Drafting a commit message before `git commit`

## Procedure

1. Inspect the scope first; never summarize from memory:

   ```bash
   git --no-pager diff --cached --stat
   git --no-pager diff --cached
   ```

   If the staged area is empty but the user meant the working tree, swap `--cached` for
   the plain diff and say which area was analyzed.

2. Group changes into 2-5 work items by intent, not by file. Renames, deletions, and the
   files they touch belong to one item.

3. Assign each item a Conventional Commit type, then prefix the matching emoji glyph
   (`🐛 fix:`, `📖 docs:`, `🆕 feat:`, `🔧 chore:`).

4. Write the main line as `<emoji> <type>: 不超过 50 字的中文摘要`: imperative mood,
   no trailing period. Put sub-items on the following lines, ordered by importance.
   Sub-items carry **no** emoji and **no** type prefix — just the work done.

5. Verify the length with [count_zh.py](./scripts/count_zh.py) before replying:

   ```bash
   python3 .github/skills/emoji-commit-summary/scripts/count_zh.py "$(cat msg.txt)"
   ```

6. Present the message in a fenced `text` block so emoji codes stay copy-pasteable.

## Emoji Table

| Emoji | Meaning | Emoji | Meaning |
| --- | --- | --- | --- |
| 🎉 | 初次提交 | 🆕 | 引入新功能 |
| 🐛 | 修复 bug | 🚑 | 重要补丁 |
| 🐧 | 修复 Linux 问题 | 🍎 | 修复 macOS 问题 |
| 🏁 | 修复 Windows 问题 | 🔒 | 修复安全问题 |
| 📝 | 撰写文档 | 📖 | 撰写文档 |
| 🔧 | 修改配置/脚本 | 🔨 | 重大重构 |
| 🎨 | 代码结构/格式 | 🔥 | 移除代码或文件 |
| 🗑️ | 废弃或删除 | ✏️ | 修复 typo |
| ➕ | 增加依赖 | ➖ | 减少依赖 |
| ⬆️ | 升级依赖 | ⬇️ | 降级依赖 |
| ✅ | 增加测试 | 🚨 | 移除 linter 警告 |
| ⚡ | 提升性能 | 🚀 | 部署功能 |
| 🐳 | Docker | 👷 | CI 构建 |
| 💚 | 修复 CI | 🔀 | 分支合并 |
| 🔖 | 版本标签 | 🚧 | 工作进行中 |

## Type Table

| Type | Meaning | Emoji |
| --- | --- | --- |
| `feat` | 新功能 | 🆕 |
| `fix` | 修复 bug | 🐛 |
| `docs` | 只改了文档 | 📖 |
| `style` | 不涉及主要逻辑（格式化等） | 🎨 |
| `refactor` | 改动了代码，既非新功能也非修 bug | 🔨 |
| `perf` | 优化性能 | ⚡ |
| `test` | 增加或修改测试 | ✅ |
| `build` | 构建流程/依赖包配置 | 🔧 |
| `ci` | CI 配置或脚本 | 👷 |
| `chore` | 其它不涉及源码和测试的修改 | 🔧 |
| `revert` | 回滚一次提交 | ⏪ |

## Rules

- Main line format is `<emoji> <type>: 摘要`; the emoji glyph always precedes the type.
- Always emit the glyph (🐛), never the shortcode (`:bug:`) — shortcodes render as text.
- Sub-items carry no emoji and no type prefix — plain descriptions only.
- One emoji per line; do not stack two emoji on the main line.
- The main line carries the dominant intent; sub-items carry the rest.
- Do not add a period at the end and do not restate the diff file-by-file.
- Do not commit or stage anything unless the user explicitly asks.

## Example

```text
🐛 fix: 修复 venv 与环境定位
- 重建半成品并回退引导 pip
- 兼容两种构建布局并检查依赖
📖 docs: 同步注释与文档
- 更新脚本更名引用
- 补充 CAN 说明
```

Chinese characters: 49 (limit 50). The Latin words (`venv`, `pip`, `CAN`) are not counted
because the limit refers to 摘要字数.
