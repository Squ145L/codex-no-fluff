# Codex 提示词替换（Claude Code 风格）

把 Codex 的内置 system prompt（`base_instructions`）换成一份按 Claude Code 工作方式重写的版本：
不再废话、不再自作免责声明、该动手就动手。

已验证：真实 exec 会话的 rollout 中 `base_instructions.text` 与该文件逐字相等，
`provenance = custom`。

## 已解决：免责声明量产

原第 121 行 "State what changed, why, how it was verified, and any remaining risk or limitation."
与第 18、37 行「不要加免责声明」直接冲突，且处于最后一章、结构权重最高，于是每份汇报都挂一条。

三处改动：

1. 第 18 行禁令从 "disclaimers" 扩到 "end-of-answer caveats"，堵住同义词缺口——模型会把
   "limitation" 当成和 "disclaimer" 不同的东西。
2. 删掉四段式清单里的"风险"格子，改成结果优先的写法，并点名 limitations / caveats /
   "things to note" / 未经测试的边界 / "this may not work for X" 一律算免责声明。
3. 只保留一个出口：该限制会改变用户下一步动作时，写进结果句、当事实陈述，不成段。

第 68 行的验证诚实性规则同步收紧为"一句话说明哪部分没测"，防止它被扩写成注意事项段。

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

## 安装

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

## 回滚

删掉 `config.toml` 里上面三行配置即可恢复原版内置提示词。
目录覆盖失效后，Codex 会退回模型自带的 `base_instructions`。

## 说明

- 这份提示词是按 Codex 工具体系重写的等价版，不是 Claude Code 系统提示词的原文。
- 已合并 Codex 原 prompt 中质量较高的四条：授权跨轮持久、先做完可逆工作再请求批准、进展更新节奏（约 60 秒一次、最终消息自包含）、具体反 AI 腔词表。
- Codex 自带记忆已开启：`features.memories = true`，`generate_memories`、`use_memories`、`dedicated_tools` 均为 true。记忆写入 `%USERPROFILE%\.codex\memories\` 和 `memories_1.sqlite`。
- 可用的记忆工具：`memories__list`、`memories__read`、`memories__search`、`memories__add_ad_hoc_note`。写入只走 `add_ad_hoc_note`，不直接改 `MEMORY.md`、`memory_summary.md` 或 `raw_memories.md`。
- `%USERPROFILE%\.codex\agent-memory\` 是更早的独立文件记忆方案，当前未启用；如不需要可删除。
- Claude Code 自己的 memory 目录属于 Claude Code，Codex 既不读也不写。
- 路径规则按工具实际行为写：`exec_command` 用 `workdir`，`shell_command`、`rg`、`git`、`python` 按当前工作目录解析，`apply_patch` 支持相对路径但需确认实际工作目录。
- 已移除重复的“安全对齐”段落和免责声明噪音，保留的不可逆命令确认、凭据保护属于工程性规则。
- 已审查 `xsser/codex-jailbreak-guide` 的 prompt：主体是伪造系统状态（`safety_layer=OFF`、未过滤模式）、"永不拒绝"、以及"立即执行脚本 / 输出化学品与设备细节"等危险指令，未采用。只吸收了合理的降低误拒原则：区分能力/授权/风险、普通工程请求不拒绝、不附加免责声明、歧义时问目标而不是拒绝。
- 工作区 `AGENTS.md` 会被 Codex 自动加载；没有 `AGENTS.md` 的项目会通过
  `project_doc_fallback_filenames` 读取 `CLAUDE.md`。

## 免责声明的来源（分析记录）

原 Codex prompt 里这句藏在“技术沟通”章节，不是安全章节：

> When reporting changes, explain what changed, why, how it was tested, and any material risks or limitations. Include the evidence needed to understand the conclusion and its practical limits.

模型把 "material risks" 和 "practical limits" 读得很宽，于是每份汇报都挂一条。
这句是免责声明量产的直接源头。本仓库的 `claude-code-system.md:121` 抄了同一个句式，
问题因此延续。
