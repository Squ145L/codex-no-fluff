# Codex 提示词替换（Claude Code 风格）

## 使用方法

1. 克隆或下载本仓库
2. **双击 `install.cmd`**
3. 新开一个 Codex 会话

撤销：双击 `uninstall.cmd`。

> 需要先装好 Codex 并至少启动过一次，否则没有 `config.toml` 可供修改。

## 这是什么

把 Codex 的内置 system prompt（`base_instructions`）换成一份按 Claude Code 工作方式重写的版本：
去掉了 Codex 自带的安全对齐段落，根除了每份汇报都挂在结尾的免责声明。

免责声明的源头是这一句，它藏在「技术沟通」章节里，不在安全章节：

> When reporting changes, explain what changed, why, how it was tested, and any material risks or limitations. Include the evidence needed to understand the conclusion and its practical limits.

模型把 `material risks` 和 `practical limits` 读得很宽，于是每次汇报都要补一句
「未经实际验证」「不能仅凭这个判断」。这句删掉后，只有在限制会改变你下一步动作时，
才允许写进结果句里当事实陈述，不许单独成段。

除此之外，该动手就动手：可逆的先做完再给你看，不先问「要不要我帮你」。

## 效果

| 场景 | 改之前 | 改之后 |
|---|---|---|
| 让它改代码 | 改完了，但本次改动未经过完整验证，建议你在实际环境中再确认一下…… | 已改，未改逻辑。测试全部通过。 |
| 问能不能跑 | 取决于具体环境，不做实测无法确定 | 不能直接跑。`detect.py` 用 `user32`，`native.py` 用 `SendInput` |
| 汇报结论 | 每份汇报结尾都挂一条「注意 / 局限性 / 未覆盖的部分」 | 说完就停 |
| 「帮我加个功能」 | 先给方案和步骤，等你确认 | 直接做，可逆的先做完再给你看 |

## 为什么需要两个文件

Codex 的加载优先级是：

```
显式 base_instructions（模型目录自带） > model_instructions_file > instructions
```

`gpt-6.1-sol` 等模型在模型目录里自带 `base_instructions`，所以只写
`model_instructions_file` 不会生效。解决办法是用 `model_catalog_json`
指向一个修改过的目录：

- `base_instructions = null`
- `model_messages.instructions_template` 留一个非空占位（校验要求二选一）

这样 `model_instructions_file` 就能接管。

## 手动安装

不想跑脚本的话：

1. 把本仓库放到任意位置（默认示例：`%USERPROFILE%\.codex\prompts`）。
2. 生成模型目录：`powershell -ExecutionPolicy Bypass -File .\refresh-catalog.ps1`
3. 在 `%USERPROFILE%\.codex\config.toml` 顶部加三行，路径按实际位置替换：

```toml
model_catalog_json = "<本仓库路径>/codex-catalog.json"
model_instructions_file = "<本仓库路径>/claude-code-system.md"
project_doc_fallback_filenames = ["CLAUDE.md"]
```

## 怎么改提示词

直接编辑 `claude-code-system.md`，保存即可。新开的 Codex 会话会读取新内容，
不需要重启或重建目录。

## 什么时候要刷新目录

OpenAI 新增或更新模型后，`codex-catalog.json` 是旧的，新模型不会出现。
运行 `refresh-catalog.ps1` 即可。

脚本会临时注释掉 `model_catalog_json`、重新 dump 默认目录、重新置空后写回，
并在 `finally` 中恢复 `config.toml`。路径全部自动推导，`codex.exe` 从 PATH
或 Codex 安装目录的最新版本子目录中查找。

## 验证方法

`codex debug prompt-input` **不反映** `model_catalog_json` 覆盖，会显示旧的
base prompt，不要用它验证。正确做法是跑一次真实会话，然后看最新的
`%USERPROFILE%\.codex\sessions\...\rollout-*.jsonl` 第一行：

```powershell
$f = (Get-ChildItem "$env:USERPROFILE\.codex\sessions" -Recurse -File |
      Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
$j = Get-Content $f -TotalCount 1 | ConvertFrom-Json
$j.payload.base_instructions.text.Length
$j.payload.base_instructions.provenance.type
```

## 说明

- 这份提示词是按 Codex 工具体系重写的等价版，不是 Claude Code 系统提示词的原文。
- 已合并 Codex 原 prompt 中质量较高的四条：授权跨轮持久、先做完可逆工作再请求批准、进展更新节奏（约 60 秒一次、最终消息自包含）、具体反 AI 腔词表。
- Codex 自带记忆已开启：`features.memories = true`，`generate_memories`、`use_memories`、`dedicated_tools` 均为 true。记忆写入 `%USERPROFILE%\.codex\memories\` 和 `memories_1.sqlite`。
- 可用的记忆工具：`memories__list`、`memories__read`、`memories__search`、`memories__add_ad_hoc_note`。写入只走 `add_ad_hoc_note`，不直接改 `MEMORY.md`、`memory_summary.md` 或 `raw_memories.md`。
- `%USERPROFILE%\.codex\agent-memory\` 是更早的独立文件记忆方案，当前未启用；如不需要可删除。
- Claude Code 自己的 memory 目录属于 Claude Code，Codex 既不读也不写。
- 路径规则按工具实际行为写：`exec_command` 用 `workdir`，`shell_command`、`rg`、`git`、`python` 按当前工作目录解析，`apply_patch` 支持相对路径但需确认实际工作目录。
- 已移除重复的“安全对齐”段落和免责声明噪音，保留的不可逆命令确认、凭据保护属于工程性规则。
- 工作区 `AGENTS.md` 会被 Codex 自动加载；没有 `AGENTS.md` 的项目会通过
  `project_doc_fallback_filenames` 读取 `CLAUDE.md`。

## 参考

把模型自带的 `base_instructions` 置空、改用 `model_instructions_file` 的办法，
参考自 [xsser/codex-jailbreak-guide](https://github.com/xsser/codex-jailbreak-guide)。
