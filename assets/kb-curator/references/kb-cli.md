# kb.cmd / kb.ps1 命令行用法（L1/L3 辅助脚本）

> 依据：`references/contract.md` §7。脚本由 **kb-architect** 实现于 `<KB>/kb.ps1`（脚本所在目录就是 KB 根——引擎自定位）。
> 本文只讲**怎么用**；脚本行为若与本文不符，以实测报错为准，并在回答里说明，**不要改契约**。

## 0. 调用方式：默认走 `kb.cmd`（附三种调用方式的实测结论）

`<KB>`（脚本所在目录）下同时有 `kb.cmd`（纯 ASCII 包装器）与 `kb.ps1`（真正实现）。
**默认一律调用 `kb.cmd`**：统一入口、纯 ASCII、exit 码透传（`exit /b %ERRORLEVEL%`）。

**实测（参考环境复测；三种调用方式对照如下）**：

| # | 调用方式 | 实测结果 |
|---|---|---|
| ① | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "<KB>\kb.ps1" status` | ✅ exit=0，正常输出知识库状态 |
| ② | 当前会话内 `& "<KB>\kb.ps1" status`（不带 Bypass） | ❌ `AuthorizationManager check failed.`（`PSSecurityException` / `UnauthorizedAccess`） |
| ③ | `& "<KB>\kb.cmd" status` | ✅ exit=0，正常输出知识库状态 |

补充实测：②之前**先执行** `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass`，同一个直调 ✅ 通过。
环境：参考环境无 `pwsh`（工具会话即 Windows PowerShell 5.1 / Desktop）；`LocalMachine = Unrestricted`，其余作用域 `Undefined`；
`kb.ps1` 无 MOTW（只有 `:$DATA` 流）。

**结论：失败原因与目录位置/ACL 无关**，是**当前 PowerShell 会话的有效执行策略**未放行未签名 `.ps1`；
`-ExecutionPolicy Bypass`（命令行参数，或进程级 `Set-ExecutionPolicy -Scope Process Bypass`）即可通过。
→ **仍建议默认走 `kb.cmd`**（统一入口、不用每次记参数、exit 码透传）；确需直调 `kb.ps1` 时**必须带 `-ExecutionPolicy Bypass`**。

`kb.cmd` 内部固定使用：

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0kb.ps1" %*
```

**不要把 `kb.cmd` 改回非 ASCII 注释**——cmd.exe 用 OEM 代码页读 `.cmd`，中文注释会被当成命令执行。

## 1. KB 根目录怎么定（每次操作第一步）+ 磁盘检查

```
1) 找 kb.cmd / kb.ps1 所在目录 —— 那就是 <KB>（引擎自定位：kb.ps1 用 $PSScriptRoot 认自己）。
2) kb.config.json 的 "root" 只是说明性字段（出厂 "."），程序不读取；不要拿它当权威。
3) 引擎在但目录尚未初始化 → & "<KB>\kb.cmd" init（幂等，只补缺、不覆盖）。
4) kb.cmd / kb.ps1 都不存在 → 引擎未安装 → 按 SKILL.md §0.0 从技能自带 engine/ 复制安装
   （不要手搓目录树、不要在别处再建一个库）。
```

`<KB>` = 引擎所在目录的绝对路径，例如 `D:\KnowledgeBase`（由用户自己选定）。

> 暂存中间件与用户原始文件分放在 `<KB>\_staging\`（OCR 中间件）与 `<KB>\_sources\`（原始 PDF 等大文件）。

**磁盘检查（收料前必做）**：任何收料 / 批量写入 / 导入大文件**之前**先跑 `& "<KB>\kb.cmd" status`（只读，不写日志）。
- 剩余空间 < `storage.warn_free_gb`（当前 20 GB）或输出 `[磁盘告警]` → **必须在回复里明确告诉用户**，并给出可清理项
  （`_staging\` 临时中间件、`_sources\` 大文件、`_inbox\_rejected\`、已驳回提案）。
- 剩余空间 < `storage.block_free_gb`（当前 5 GB）→ `add` **拒绝收料并 exit=1**；停止收料，先告知用户、等指示。
- 阈值只从 `<KB>\kb.config.json` 的 `storage` 读，**不写死在技能里**（改配置即可调整）。

调用风格（Windows / PowerShell 5.1 与 7 通用）：

```powershell
$KB = "<KB>"                  # 知识库根目录 = kb.cmd / kb.ps1 所在目录（引擎自定位）
& "$KB\kb.cmd" status         # 收料/批量写入前先看磁盘
& "$KB\kb.cmd" list-queue
```

## 2. 命令表（契约 §7，参数名固定）

| 命令 | 作用 | 示例 | 何时用 |
|---|---|---|---|
| `status` | **只读**打印：知识库根、所在磁盘剩余空间（含预警线/拒绝线）、待审/已批准/已驳回计数、L0/L1/L3/日志计数、规范文件齐备性（**不写日志**） | `& "<KB>\kb.cmd" status` | **每次收料/批量写入/导入大文件前必跑**；用户问「还剩多少空间 / 知识库所在盘满了吗 / 现在什么状态」 |
| `init` | 初始化目录布局（kb.config.json / _inbox / _review / _system / _templates / library / pages） | `& "<KB>\kb.cmd" init` | 首次使用；幂等，可重复跑；也会打印剩余空间 |
| `add -Path <file> [-Category <c>]` | 把一份文件加入 `_inbox/` 并登记（可指定大类） | `& "<KB>\kb.cmd" add -Path "D:\dl\vite.md" -Category 技术工程` | 用户给的是文件路径 |
| `list-queue` | 列出所有待审提案（`_review/queue/`） | `& "<KB>\kb.cmd" list-queue` | 用户问"有哪些待审" |
| `show <id>` | 显示某提案完整内容 | `& "<KB>\kb.cmd" show kb-20261009-0001` | 用户要看细节 / 你确认提案内容 |
| `approve <id>` | 批准（L1 落盘 + 提案归档 + 记日志 + 打印 agent 待办） | `& "<KB>\kb.cmd" approve kb-20261009-0001` | 用户说"批准" |
| `reject <id> -Reason "..."` | 驳回并记录理由 | `& "<KB>\kb.cmd" reject kb-20261009-0001 -Reason "来源不可靠"` | 用户说"驳回" |
| `search <query>` | 在 L1/L3 文件里做关键词检索 | `& "<KB>\kb.cmd" search "vite 端口"` | 需要看原文文件（L2 语义检索用 `engram_search`） |
| `page <大类>` | 输出 / 维护某大类知识页 | `& "<KB>\kb.cmd" page 技术工程` | 用户问"这个大类有什么" |
| `log [-Tail N]` | 看操作日志 | `& "<KB>\kb.cmd" log -Tail 20` | 用户问"最近动了什么" |

`add` **不生成提案**，但它是**唯一正确的收料入口**，会替你做四件事：分配 id（`kb-<yyyymmdd>-<4位序号>`，当日最大序号 +1）、
算 `content_hash` 并查重（重复 → 提示疑似重复并 **exit=1** 拒绝）、规范落 `_inbox/<id>-<slug>.md` 原文副本、
生成 `_inbox/<id>-<slug>.meta.md` 初始元数据（含 `category_basis` / `inbox_path` / `l2_content_suggestion` / 建议 priority/confidence）。
**不要手搓 `_inbox/` 文件名、不要自己算 id**（会撞号、丢查重护栏、`inbox_path` 与脚本预期不符）。
`add` 之后**提案要你自己**按 `_templates/review-proposal.md` 写到 `_review/queue/<id>.md`。

## 3. 分工：kb.cmd 还是 engram 工具？

| 我要做的事 | 用哪个 |
|---|---|
| 语义检索库内知识 | `engram_search`（L2，混合检索）→ 需要全文再 `engram_examine` / `kb.cmd search` |
| 关键词找原文文件 | `kb.cmd search` |
| 看 / 批准 / 驳回提案 | `kb.cmd list-queue` / `show` / `approve` / `reject` |
| 写入记忆条目 | `engram_save` / `engram_update`（**`kb.cmd` 不负责写 engram**） |
| 看知识页 | `kb.cmd page <大类>` |
| 审计轨迹 | `kb.cmd log` + `_system/log.jsonl` |

**关键**：`kb.cmd approve` 只处理**文件与登记**（L1 落盘、提案归档、写日志、打印待办）；
**写入 L2（engram）必须由你用 `engram_save` / `engram_update` 显式完成**，脚本不会替你调工具。
所以 `approve` 之后要按 `references/review-workflow.md` §4 做 **agent 侧三步**（L2 → L3 → 归档提案 status 改 `indexed` + 补 `l2-saved` 日志），缺一步都不算"已入库"。

## 4. 标准操作序列（照抄）

**喂一份文件**：
```powershell
$KB = "<KB>"                            # = kb.cmd / kb.ps1 所在目录
& "$KB\kb.cmd" status                      # ⓿ 先看磁盘（告警线/拒绝线；有告警必须告诉用户）
& "$KB\kb.cmd" add -Path "D:\dl\某资料.md" -Category 技术工程
& "$KB\kb.cmd" list-queue                          # 确认收料成功
```
随后按 SKILL.md §4 写提案到 `_review/queue/<id>.md`，再回话给用户。

**用户说"批准 kb-20261009-0001"**：
```powershell
& "$KB\kb.cmd" show kb-20261009-0001       # 先复看提案内容（确认没记错）
& "$KB\kb.cmd" approve kb-20261009-0001    # ① L1 落盘 + ② 提案归档 + ③ 记日志 + 打印待办（这三件不要再做！）
# ④ 你调用 engram_save / engram_update 写 L2（脚本不做）
# ⑤ 你更新 pages/<大类>.md（脚本默认不动 pages，除非加 -UpdatePage）
# ⑥ 你把 _review/approved/kb-20261009-0001.md 的 status 改成 indexed，并补一行 l2-saved 日志
& "$KB\kb.cmd" log -Tail 5                 # 核对日志（target/note 两列应有内容）
```
**⚠️ 不要自己先写 `library/`（L1）**：`approve` 落盘遇同名会静默生成 `…-2.md`，同一份资料在 L1 出现两张卡（已实测）。

**用户说"驳回，理由是…"**：
```powershell
& "$KB\kb.cmd" reject kb-20261009-0001 -Reason "来源不可靠"
& "$KB\kb.cmd" log -Tail 5
```

## 5. 故障排查

| 现象 | 原因 / 处理 |
|---|---|
| `AuthorizationManager check failed` | 执行策略未放行未签名 `.ps1`——**与目录位置/ACL 无关**（旧解释已实测不成立）。改用 `kb.cmd`；确需直调 `kb.ps1` 就加 `-ExecutionPolicy Bypass`（见 §0 实测表） |
| `[磁盘告警] …本次收料继续，但请立即提醒用户清理磁盘` | 剩余 < `storage.warn_free_gb`（20 GB）。**必须在回复里告诉用户** + 给可清理项；本次收料仍继续（exit=0） |
| `知识库所在磁盘剩余空间不足 … 已拒绝本次收料` | 剩余 < `storage.block_free_gb`（5 GB）。**停止收料**（exit=1），先告知用户等指示；**不要改写到别的盘绕过** |
| 用户问「知识库所在盘还剩多少 / 快满了吗」 | 跑 `& "<KB>\kb.cmd" status`，念库根 + 剩余空间 + 各层计数，并给可清理项（`_staging\` / `_sources\` / `_inbox\_rejected\`） |
| `kb.cmd` 输出一堆 `'xxx' is not recognized as an internal or external command` | `kb.cmd` 里被写入了非 ASCII 注释。保持该文件纯 ASCII |
| `kb.cmd` / `kb.ps1` 都不存在 | 引擎未安装 → 按 SKILL.md §0.0 从技能自带的 `engine/` 复制安装；不要手写替代脚本，也不要假称已入库 |
| 报"未初始化" | 跑 `init`（幂等） |
| `add` 报路径不存在 | 先确认文件真实存在（`Test-Path`），中文路径加引号 |
| `approve` 后 engram 里没有 | 正常——脚本不写 engram，是你漏了 `engram_save` 这一步；补做并记日志 |
| `approve` 后 `pages/` 没变 | 正常——默认不动 pages，知识页要你自己综述后更新 |
| 中文乱码 | kb.ps1 必须 UTF-8 **with BOM**（5.1 读中文所需）；不要用会吃掉 BOM 的写入方式覆盖它 |
| 参数名报错 | 以脚本内 param 声明为准，并在回答里说明差异；**不改契约** |
| 命令幂等性 | `init` 可重复跑；重复 `add` 同一文件会提示疑似重复并以非 0 退出 |
| `library/` 里出现同名 `…-2.md` 两张卡 | 你在 `approve` 之前自己写了一份 L1。删掉多余那份；L1 一律由 `approve` 落盘 |
| `kb.cmd log` 的 id 列与详情列全空 | 你写日志用了 `id` / `detail`；Cmd-Log 读的是 `target` / `note`，改用这两个字段名 |

## 6. 安全与约束（继承契约）

- 纯 PowerShell，无外部依赖（免费硬约束：不引入付费服务）。
- **不得删除已有资料**——只移动 / 追加；`approve` 落盘遇同名加 `-2` 后缀，绝不覆盖。
- 出错给中文可读信息。
- 所有改变状态的操作都要在 `_system/log.jsonl` 留痕（脚本做或你做，但必须有）。
