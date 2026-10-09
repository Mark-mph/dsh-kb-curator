---
name: kb-curator
description: 本地智能知识储备体系的策划与维护（三层：L1 原文库 / L2 engram 记忆 / L3 知识页）：喂资料、自动分类、生成待审提案、用户批准后才入库、五状态审核、来源引用、冲突仲裁与优先级裁定、召回答疑。当用户说「喂资料」「把这份资料存进知识库」「记到知识库」「归档一下」「有哪些待审」「审核」「批准入库」「通过这条」「驳回」「要改」「查库」「知识库里有没有」「资料冲突」「按优先级裁定」「knowledge base」「ingest」「curate」「approve」「arbitrate」「recall」「add to my KB」时使用本技能。
---

# 智能知识储备体系 · kb-curator

> 唯一事实来源：`references/contract.md`（冻结契约 v1；本技能自带副本）。
> 本技能与契约冲突时，**以契约 §5 仲裁算法、§6 审核工作流为准**；发现契约本身有问题 → 报告用户/Lead，**不得自行改契约、不得自创规则**。

---

## 0.0 引擎在哪、首次怎么装（先读这节）

1. **引擎随本技能一起分发，位于本技能基目录下的 `engine/`。**
   模型每次加载技能时会在 `<skill_resources>` 里收到本技能基目录的绝对路径（形如 `Base directory for this skill: <path>`）——
   用它拼出引擎的真实路径：`<技能基目录>\engine\`。里面有 `kb.cmd`（唯一推荐入口）、`kb.ps1`（实现）、`kb.config.json`、`README.md`、`_system/`、`_templates/`。

2. **首次使用**：把整个 `engine/` 目录**复制**到用户指定的知识库根目录（就是 `<KB>`），然后建库：

   ```powershell
   & "<KB>\kb.cmd" init
   ```

   `init` 是**幂等**的：只补缺失的目录与文件，**绝不覆盖**已有内容，可以反复跑。

3. **复制完的那个目录本身就是知识库根目录**，本技能里的 `<KB>` 指的就是它。
   引擎是**自定位**的（`kb.ps1` 用 `$PSScriptRoot` 认自己所在的目录），`kb.config.json` 的 `root` 只是说明性字段、程序不读取——
   所以**换目录、换盘、改名都不用改任何配置**。

4. **运行前提：Windows + Windows PowerShell 5.1。**
   `kb.cmd` 是**唯一推荐入口**（纯 ASCII 包装器，内部固定带 `-ExecutionPolicy Bypass`）；
   确需直调 `kb.ps1` 时必须自己加 `-ExecutionPolicy Bypass`，否则报 `AuthorizationManager check failed.`（见 §3 与 `references/kb-cli.md` §0）。
   **非 Windows 平台目前用不了引擎**（引擎是 PowerShell 实现，未提供跨平台版本）——遇到非 Windows 环境请**如实告知用户**，不要假装能跑。

5. **L2（engram 记忆层）需要额外安装 `@kenz1117/dsh-engram` 插件。**
   没装就**只做 L1 + L3**；本技能凡涉及 L2 的步骤（`engram_save` / `engram_update` / `engram_search` / `engram_facts` / `engram_assess` 等）一律按「**需要 engram，未安装则跳过并告知用户**」处理——
   不要用文件模拟 engram，也不要假装写入成功（见 §9、§11）。

---

## 0. 20 秒速查卡（用户说 X → 你做 Y）

| 用户说 | 你做的命令序列 | 落盘结果 |
|---|---|---|
| 「喂这份资料」+ 贴文本 / 给文件路径 / 给网址 | **⓿ 先 `& "<KB>\kb.cmd" status` 看磁盘**（告警线或剩余 < 20 GB → 必须在回复里告诉用户，见 §1 铁律 4 与 §3）① 把原文落成文件后 `& "<KB>\kb.cmd" add -Path <文件>`（**必须走脚本**：它分配 id、算 `content_hash` 查重、生成 `.meta.md`；贴文本/网址先写成临时 `.md` 再 add）② 读 `_inbox/<id>.*.meta.md` 与 L0 原文副本 ③ 写提案 `_review/queue/<id>.md`（frontmatter 字段集照 `_templates/review-proposal.md`）④ 回话给用户看提案摘要 | 只写 L0 `_inbox/` 与 `_review/queue/`；**不碰 L1/L2/L3** |
| 「有哪些待审 / 给我看看」 | `& "<KB>\kb.cmd" list-queue` | 只读 |
| 「看看第 N 条 / 展开 kb-20261009-0001」 | `& "<KB>\kb.cmd" show <id>` | 只读 |
| 「批准 / 通过 / 入库 / 可以」 | `& "<KB>\kb.cmd" approve <id>` —— **脚本已落 L1 + 归档提案 + 写日志，这三件绝对不要重做**（重做会生成 `…-2.md` 重复卡）；你接着按 §6 做 agent 侧三步：`engram_save`/`engram_update` 写 L2 → 更新 `pages/<大类>.md` → 把 `_review/approved/<id>.md` 的 status 改 `indexed` 并补一行 `l2-saved` 日志 | L2 + L3 + 归档提案状态 + `log.jsonl`（**L1 由脚本落，你不要自己写**） |
| 「驳回 / 不要 / 不通过」+ 理由 | `& "<KB>\kb.cmd" reject <id> -Reason "<用户原话>"` | 提案进 `_review/rejected/`，L1 丢弃或移 `_inbox/_rejected/`，记日志 |
| 「要改：把优先级调成 5 / 类别改成 产品业务」 | 改提案文件 → 状态回 `proposed` → 重新贴给用户确认 | 只改 `_review/queue/<id>.md` |
| 「知识库里有没有 … / 帮我查 …」 | `engram_search(query=..., scope=...)`（**默认不带 `room`**——房间每 9 条分裂，按房间查会漏，见 §9）→ 需要全文时 `engram_examine(ids=[...])` → `engram_assess` 过证据门 → 回答每条带 `[src:<L1-id>]` | 只读 |
| 「帮我讲讲 X / 这个怎么用 / 原理是什么」 | **先取消化层**：读 `pages/<大类>.md` 里对应主题小节（核心结论 / 原理与推导 / 方法与步骤 / 适用条件与边界 / 易错点）→ 不够再 `engram_search` 取 L2 → 还缺原文细节时读 L1 并挂 `[src:<L1-id>]` → `engram_assess` 过证据门。细节见 §8 | 只读 |
| 「这条和库里的矛盾 / 按优先级裁定」 | 严格跑 §7 八步：① 提取冲突 → ② 同领域 → ③ 时效 → ④ **正误推理**（判谬误要给出**可检验**理由：推导 / 反例 / 量纲 / 定义冲突；判定为错先告知用户 + 建待审记录）→ ⑤ 来源等级 → ⑥ priority → ⑦ confidence → ⑧ 仍打平才报 `conflict`，**不选边** | 冲突提案 + 明确告知用户（`by: agent`、`pending_user: true`） |
| 「看看某大类的知识页」 | `& "<KB>\kb.cmd" page <大类>`；没有就说明「该大类还没有综述页，需要先有已批准的条目」 | 只读 |
| 「这个说法过时了 / 换成新的」 | 新资料照喂 → 批准时用 `engram_update(id=<旧条目id>, content=...)` 归并，旧条目标「被取代」 | 取代链保留 |
| 「最近动了什么」 | `& "<KB>\kb.cmd" log -Tail 20` | 只读 |
| 「知识库怎么建的 / 现在什么状态」 | `& "<KB>\kb.cmd" status`（库根 + 磁盘剩余 + 待审/批准/驳回计数 + 各层文件数）+ 读 `kb.config.json`、`_system/taxonomy.yml`，用中文汇报 | 只读 |
| 「知识库所在盘快满了吗 / 还剩多少空间 / 知识库占多大」 | `& "<KB>\kb.cmd" status`（只读，不写日志）；有 `[磁盘告警]` 或剩余 < 20 GB → 明确告知用户并给可清理项（`_staging\` 临时件、`_sources\` 大文件、`_inbox\_rejected\`、已驳回提案） | 只读 |

**一句话记住**：**用户不点头，L2/L3 一个字都不写。**

---

## 1. 四条铁律（做任何事之前先过一遍）

1. **安全阀（硬约束，无例外）**：状态不是 `approved` 的条目，**绝对不允许**写入 L2（`engram_save` / `engram_update` / `engram_facts`）与 L3（`pages/<大类>.md`）。
   只有 `proposed` / `rejected` / `needs_edit` 状态时，你只能写 `_inbox/`、`_review/queue/`、`_system/log.jsonl` 这三处。
   **任何"我先存进 engram 等用户批准"的做法都是违规**——没有"临时写入"这个操作。
2. **免费硬约束**：整条链路**只有云端模型（DeepSeek）花钱**。
   - 禁止 Hindsight 云（`hindsight-coding-agents` 插件已禁用，不要重新启用、不要调用它的服务）。
   - 禁止任何付费嵌入 / 向量 API（OpenAI embeddings、Jev、商用向量库 SaaS 等）。
   - 嵌入只用 engram 自带的**本地**模型 `Xenova/bge-small-zh-v1.5`（512 维 q8，纯 CPU 离线，免费），不配置任何远程 embedding endpoint。
   - 联网搜索用免费的现有搜索工具；不调用付费检索 API。
   - 不给任何配置文件写入付费服务的默认地址或 key。
3. **引用必须可回溯**：凡引用库内条目的回答、提案、知识页，都必须写出 `[src:<L1-id>]`（如 `[src:kb-20261009-0001]`）。
   没有 `[src:...]` 的 L2 条目**视为不合格条目**，不得写入。库外/未审核的联网内容标 `[web:<url>]`（未审核），且**不参与仲裁**。
4. **磁盘空间（用户硬要求：知识库所在盘快存满必须提前告诉我）**：知识库根目录 `<KB>` 由用户选定（用户要求集中一处，不要存得到处都是）。
   - **任何收料 / 批量写入 / 导入大文件之前，先跑 `& "<KB>\kb.cmd" status`**（只读，不写日志）。
   - 看到 `[磁盘告警]` 或剩余空间 < `storage.warn_free_gb`（当前 20 GB）→ **必须在回复里明确告诉用户**，并给出可清理项。
   - 看到拒绝线（< `storage.block_free_gb`，当前 5 GB）→ 脚本会拒绝收料（exit=1）；**停止收料**，先把情况告诉用户、等指示。
   - 阈值在 `<KB>\kb.config.json` 的 `storage` 里，**不写死在技能里**，改配置即可调整。

---

## 2. 三层架构（必须理解，不许混层）

| 层 | 是什么 | 放在哪 | 谁写 | 允许的粒度 |
|---|---|---|---|---|
| **L1 原始库** | 资料原文（Markdown），人眼可看、可版本管理 | `<KB>/library/<大类>/<子类>/<yyyy-mm-dd>-<slug>.md` | 用户批准后由 **`kb.cmd approve`** 落盘（**agent 不要自己写**） | **原文逐字**，不改写、不摘要 |
| **L2 检索层** | 记忆条目（事实/偏好/决策/事件/技法），进 engram 做混合检索 | engram 插件的本地 SQLite 库（具体位置由 engram 插件决定） | 用户批准后 `engram_save` | **提炼后的一句话命题**，必须带 `[src:<L1-id>]` |
| **L3 知识页** | 每个大类一张**消化页**（把已批准的 L1/L2 消化成可直接运用的知识块） | `<KB>/pages/<大类>.md` | 用户批准后更新 | **消化层**：五要素（概念定义 / 原理推导 / 方法步骤 / 适用条件与边界 / 易错点）+ 索引，不是原文堆放处 |

**L3 纪律（契约 §1 关键纪律）**：几千份原文**不许**塞进知识页。
- L1 只放原文；L2 只放提炼条目；L3 只放某大类的总览、目录、跨条目的综合结论。
- 判断标准：如果一段内容是把 L1 原文整段搬过去 → 放错了，应该留在 L1，L3 只写一句摘要 + 指向 `[src:<L1-id>]` 的链接。
- 单张 L3 页超过约 200 行时，把细节下沉到 L1/L2，只保留索引与结论。

细节见 `references/architecture.md`。

---

## 3. KB 根目录怎么找 + 先看磁盘（每次操作第一步）

**正式根目录 = `<KB>`**（用户选定的知识库根目录；用户硬要求：所有资料集中在这一个文件夹，不散落到别处。引擎就装在这个目录里，`kb.cmd` / `kb.ps1` / `kb.config.json` 都在其中）。
**引擎是自定位的**：`kb.ps1` 用 `$PSScriptRoot` 认自己所在的目录，那个目录就是知识库根目录；改名 / 换路径 / 换盘都**不需要改任何配置**。

```
1) 找 kb.cmd / kb.ps1 所在目录 → 那就是 <KB>（不要另建第二个库）。
2) kb.config.json 的 "root" 只是说明性字段（出厂为 "."），程序**不读取**它：
   不要把 root 当权威，也不要靠它解析根目录。
3) 目录里没有 kb.cmd / kb.ps1 → 引擎尚未安装 → 按 §0.0 安装；不要手搓目录树、不要在别处再建一个库。
4) 目录已装引擎但尚未初始化 → 执行：& "<KB>\kb.cmd" init（幂等，只补缺、不覆盖）
   （不要自己 mkdir 全套目录——目录布局由 kb.ps1 init 负责）
```

`<KB>` = 引擎所在的那个绝对路径（用户选定的知识库根目录）。

**磁盘检查（收料前必做）**：任何收料 / 批量写入 / 导入大文件**之前**先跑 `& "<KB>\kb.cmd" status`（只读，不写日志）。
- `[磁盘告警]` 或剩余 < `storage.warn_free_gb`（当前 20 GB）→ **必须在回复里明确告诉用户**「知识库所在盘快满了」+ 可清理项
  （`_staging\` 临时中间件、`_sources\` 大文件、`_inbox\_rejected\`、已驳回提案）。
- 低于 `storage.block_free_gb`（当前 5 GB）→ 脚本**拒绝收料（exit=1）**；停止收料，先告知用户并等指示。
- 阈值只从 `<KB>\kb.config.json` 的 `storage` 读，**不在技能里写死**。

执行方式（实测结论，详见 `references/kb-cli.md` §0）：
- **默认走 `kb.cmd`**（统一入口、纯 ASCII 包装器、exit 码透传）：`& "<KB>\kb.cmd" status`。
- 若确需直调 `kb.ps1`，**必须带 `-ExecutionPolicy Bypass`**，例如
  `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "<KB>\kb.ps1" status`；
  直接 `& "<KB>\kb.ps1" status` 会报 `AuthorizationManager check failed.`（与目录位置无关，
  是会话进程执行策略的问题——实测记录见 `references/kb-cli.md` §0，不要再用旧的「沙箱 ACL」解释）。

`kb.cmd` 支持的命令（契约 §7，参数名固定，与 `kb.ps1` 完全相同）：

```
status
init
add -Path <file> [-Category <c>]
list-queue
show <id>
approve <id>
reject <id> -Reason "..."
search <query>
page <大类>
log [-Tail N]
```

详见 `references/kb-cli.md`。脚本由 kb-architect 实现；若某命令实测参数不同，以 `kb.ps1` 实际行为为准并在回答里说明，**不要改契约**。

---

## 4. 喂料流程（INGEST，7 步，逐条执行）

**触发**：用户贴了一段文本 / 给了一个文件路径 / 给了一个网址 + 表达"存下来 / 喂进去 / 归档"。

> **第 1 步必须是 `kb.cmd add`，不许自己往 `_inbox/` 写文件、也不许自己算 id。**
> 脚本负责 id 分配、`content_hash` 查重（重复直接 exit=1 拒绝）、规范命名与 `.meta.md` 初始元数据。
> 绕过它 = 丢掉查重护栏 + id 撞号 + 提案里的 `inbox_path` 与 `approve` 的预期不符。

```
1. 收料（脚本做，唯一入口）
   - 文件：& "<KB>\kb.cmd" add -Path "<文件绝对路径>"
   - 贴文本 / 网址：先把原文**逐字**写成临时 .md（网址先用免费抓取工具取正文；抓不到就如实说
     "抓取失败"，不要把标题或搜索摘要当正文），再 & "<KB>\kb.cmd" add -Path "<临时文件>"
   - 用户明确指定了大类时可加 -Category <大类>
   - 输出 [疑似重复] 且 exit=1 → 停下问用户"这份资料已存在（id=…），是否要更新版本？"，
     用户确认要再收一份时才加 -Force

2. 读初始元数据（脚本刚生成的）
   - _inbox/<id>-<slug>.meta.md：id / title / category_suggested / category_basis /
     subcategory_suggested / source_type / source_rank / content_hash / priority_suggested /
     confidence_suggested / proposition_key / l2_content_suggestion / inbox_path / origin_path
   - L0 原文副本：_inbox/<id>-<slug>.md（这就是批准后要落 L1 的原文，逐字不改）

3. 确认命题
   - 同 proposition_key 的不同说法不算重复：照走流程，仲裁时按 proposition_key 聚类比来源等级。

4. 分类（§5）
   - 以 meta 的 category_suggested / category_basis 为初值，按 _system/taxonomy.yml 复核；
     不确定就用 未分类，并在提案里写"建议分类：未分类（原因：…），请用户指定"。
   - proposition_key 取脚本建议值，或修正为 `大类/子类/<命题 slug>`。

5. 评估四要素
   - priority（1-5，5 最高，默认 3）
   - confidence（0-1，agent 初判，默认 0.8）
   - source_type：user_file | user_text | web
   - 时效：valid_from / valid_until（空 = 长期有效）；涉及版本号、价格、政策、人事的内容
     **必须**填 valid_until 或明确标注"时效敏感"。
   - source_rank（仲裁用）：user_provided=100 / user_approved_web=60 / unapproved_web=20。

6. 生成提案 <KB>/_review/queue/<id>.md（状态 proposed）
   - 必含 6 项内容（契约 §6）：原文摘要 / 建议分类 / 建议优先级 / 置信度 /
     **将要写入 engram 的条目正文（含 [src:<id>]）** / 将要更新的知识页 diff
     —— 知识页 diff 按 §8 的**五要素**写消化预览（核心结论 / 原理与推导 / 方法与步骤 / 适用条件与边界 / 易错点），
     这是 `proposed` 阶段唯一允许的"消化"落点（**不许提前写进 pages/**）。
   - **frontmatter 字段集以 <KB>/_templates/review-proposal.md 为准，所有字段都写在 frontmatter 里**
     （id / title / category / subcategory / source_type / content_hash / status / priority /
     confidence / proposition_key / inbox_path / l2_kind / l2_scope / l2_content …）：
     `kb.cmd approve` **只读 frontmatter**，字段写在正文里等于没写。而且当前脚本是**静默降级**、不报错：
     缺 `inbox_path` → 按 id 在 `_inbox/` 兜底找副本（找不到才 exit=1）；缺 `category` → 落 `未分类/通用/`；
     缺 `title` → 文件名退化成 `<日期>-<id>.md`；缺 `l2_content` → 打印的 `engram_save(content="")` 是空的。
     唯一提示是 `list-queue` 的 `[警告]`。（已实测）
   - id / content_hash / inbox_path / added_at 直接抄 meta，**不要自己编**。

7. 回话给用户
   - 用中文列：建议分类、优先级、置信度、将入库的 L2 正文（一行）、将改的 L3 位置、来源标记。
   - 明确问一句"**批准 / 驳回 / 要改？**"，然后停下等用户回答。
   - 不要在这条消息里去写 L1/L2/L3。
```

**id 规则**：`kb-<yyyymmdd>-<4位序号>`，由 **`kb.cmd add` 分配**（当日最大序号 +1），**不要自己算**；提案文件名就用脚本给的那个 id。

---

## 5. 分类（taxonomy）

- 大类清单来自 `_system/taxonomy.yml`，初始为：`技术工程` · `产品业务` · `学术研究` · `生活健康` · `财务投资` · `人文社科` · `工具流程` · `未分类`（见契约 §2）。
- 判定顺序：① 文件名/标题关键词命中 taxonomy 触发词 → 用该大类；② 正文主题匹配 → 用该大类；③ 跨类（如"用 Python 做投资回测"）→ **按用户真实用途归类**，以"这份资料解决什么问题"为准，另一类写进 tags；④ 都不确定 → `未分类`，**不硬猜**，并在提案里写"建议分类：未分类（原因：…），请用户指定"。
- 用户改分类时：只改提案，不改已入库条目；已入库条目的改类走"新提案 + 批准 + engram_update 归并"。
- 大类增改要写进 `_system/taxonomy.yml`（kb-architect 的脚本/模板负责结构，你只追加用户明确要求的新类）。

---

## 6. 五状态审核工作流 + 安全阀

```
inbox ──agent 提案──> proposed ──用户批准──> approved ──入库──> indexed
                        │                     ▲
                        ├──用户驳回──> rejected
                        └──用户要改──> needs_edit ──agent 改完──> proposed
```

| 状态 | 含义 | 你此刻能写的地方 |
|---|---|---|
| `inbox` | 用户刚扔进来，还没处理 | `_inbox/`、`_system/log.jsonl` |
| `proposed` | 已生成提案，等用户裁决 | `_review/queue/`、`_inbox/`、`_system/log.jsonl` |
| `needs_edit` | 用户要求修改 | 同上，改完回 `proposed` |
| `rejected` | 用户驳回 | `_review/rejected/`、`_inbox/_rejected/`、`_system/log.jsonl` |
| `approved` → `indexed` | 用户批准并已入库 | L1 + L2 + L3 + `_review/approved/` + `_system/log.jsonl` |

**批准 = 脚本做前几件（已经做完，绝不要重做）+ agent 接着做后三步**：

```
【kb.cmd approve <id> 已经做完的 —— 不要重做】
① L1 落盘：<KB>/library/<大类>/<子类>/<yyyy-mm-dd>-<slug>.md
   （slug 由提案 `title` 生成；实际路径以 approve 打印的 `[① L1 落盘]` 一行为准）
   frontmatter 由脚本从提案 frontmatter 生成，**status: approved**（不是 indexed）；
   原文取自 _inbox/ 的 L0 副本，逐字写入。
   ⚠️ 你若先自己写了一份 L1，脚本遇同名会走防覆盖分支、**静默生成 `…-2.md`** →
      同一份资料在 L1 出现两张卡（已实测）。**永远不要自己写 L1。**
② 提案归档：_review/queue/<id>.md → _review/approved/<id>.md
③ 写日志：action=approve、target=<id>、by=user、l2_pending=true
   （只有显式 `approve <id> -UpdatePage` 时脚本才机械追加一行索引到 pages/；默认不动 L3）

【agent 必须接着做，缺一步都不算"已入库"】
④ L2 写入：先做相似度检查（engram_search 同命题，默认不带 room）
     高度相似 → engram_update(id=<旧条目id>, content=<新正文>) 归并
     确为新命题 → engram_save(content=<提案里的 l2_content>, kind=<英文 kind：fact|preference|decision|episode|skill>, scope=<l2_scope>, placard="<yyyy-mm 主题>")
⑤ L3 更新：<KB>/pages/<大类>.md（**消化层**：为该主题新增/补全 `## <主题>` 小节，
     按 核心结论 / 原理与推导 / 方法与步骤 / 适用条件与边界 / 易错点 / 相关条目 六段写全 —— 见 §8 与
     `references/learning.md`；「已入库条目索引」追加一行，只写结论与 [src:<L1-id>] 链接，
     禁止粘贴原文；同时改对 entry_count / updated_at）
⑥ 收尾（两步）：
     - 把 _review/approved/<id>.md 的 status 改成 indexed
       （**L1 原文卡的 status 保持脚本落定的 approved，勿手改**）；
     - 追加一行日志。

log.jsonl 一行一事件，字段与 kb.ps1 的 Write-KbLog 一致（`kb.cmd log` 只渲染 ts/action/target/note 四列）：
{"ts":"<ISO8601>","actor":"agent|user|kb.ps1","action":"add|propose|approve|reject|edit|l2-saved","target":"<id>","note":"<中文短句详情>","by":"agent|user","id":"<id>","l2_pending":<true|false>}
⚠️ 不要用旧字段名 id/detail：Cmd-Log 读的是 target/note，写错则 id 列与详情列全空（已实测）。
```

**驳回**：提案移 `_review/rejected/`（保留驳回理由原文），L1 丢弃或移 `_inbox/_rejected/`，记日志。**不删除用户资料**——只移动/追加，永不 `Remove-Item` 原文。

**安全阀表述（照抄进回答，让用户放心）**：
> 未批准的内容只存在于 `_inbox/` 与 `_review/queue/`，不会进 engram（L2），也不会进知识页（L3）。

细节见 `references/review-workflow.md`。

---

## 7. 冲突仲裁八步（契约 §5，冻结，逐条照做，不许自创规则）

输入：问题 q、候选条目集合 C（来自 L2 检索 + 可能的联网搜索）。

```
1) 提取冲突：按 (category, subcategory, proposition_key) 聚类，同一组内出现不同结论才算冲突。
2) 同领域过滤：只保留 category/subcategory 与 q 相关的条目。
3) 时效过滤：valid_until < now 的剔除；valid_from > now 的降级为「未来条目」
   —— 不参与裁定，但要在回答里提示"存在尚未生效的说法"。
4) 正误推理（本步最重要）：对每条冲突说法做**可检验**检查 ——
   a. 内部自洽（推导 / 计算 / 量纲 / 逻辑）；
   b. 与公认基准一致（教材、标准定义、学科共识、官方规范）；
   c. 与库内其他高置信条目相容。
   - 能明确判定为谬误 → verdict=erroneous：**必须显式告知用户**（绝不许静默丢弃），
     附具体理由（推导 / 反例 / 量纲 / 定义冲突），并生成待审记录交用户最终确认。
   - 无法判定（都自洽，或属不同条件 / 版本 / 参数 / 模型假设）→ 继续下一步。
   - 硬约束：**禁止仅凭"更常见 / 更符合直觉 / 感觉更权威"判错**；
     判错是提案不是终审，用户可推翻；判错不删条目，原文保留。
5) 组内比来源等级 source_rank：user_provided=100 > user_approved_web=60 > unapproved_web=20。
6) 同等级比 priority（5 最高）。用户尚未规定优先级 → agent 自行判断并标 `by: agent`、`pending_user: true`。
7) 仍相同比 confidence（0-1）打破平局。
8) 仍无法分出胜负 → outcome="conflict"：
   - 不选边；把涉及条目标 conflicted；
   - 生成一条冲突提案放入 _review/queue/；
   - 回答中显式写出「库内存在冲突说法，已列入待审队列，请你裁定」。
（第 ⑨ 条）库内 vs 联网冲突：联网结果同样先过第 ④ 步正误推理；库内 user_provided 条目优先；
未审核的 web 结果不参与裁定，只能作为「补充视角」附在答案末尾并标注未审核。
```

输出：`{chosen_ids, outcome: resolved|conflict, conflict_ids, verdicts, 依据说明}`，其中
`verdicts = [{id, verdict: sound|erroneous|undecidable, reason, basis}]` 是第 ④ 步产出；
`verdict=erroneous` 必须**同时**出现在「给用户的显式告知」与「待审队列」两处。
**依据说明要写人话**：哪一条胜出、按第几步胜出（例："第 ⑤ 步，用户提供的说法来源等级 100 高于已审联网资料 60"）；判错时写清**可检验理由**。

硬性禁止：
- 不许"更符合常识所以选它"——仲裁看 正误推理 → source_rank → priority → confidence，不看你的偏好。
- 不许跳过第 ④ 步正误推理直接比来源等级（顺序是刚性的）。
- 不许悄悄丢掉失败方或被你判错的一方：冲突与判错都必须显式告诉用户。
- 不许用未审核的 web 结果推翻库内条目。

细节与伪码见 `references/arbitration.md`。

---

## 8. 消化学习层（不只是存，还要理解、会讲、会用）

**触发**：每份资料批准入库时产出；用户问「讲讲 X / 怎么用 / 原理是什么」时取用。

**五要素（每份资料都要产出；原文没涉及就写明"原文未涉及"，不许跳过）**：
① 概念与定义（术语 / 符号 / 单位）② 原理与推导链（为什么成立、前提假设）③ 方法与步骤（可执行流程）
④ 适用条件与边界 ⑤ 易错点与常见误区 + 与其他知识的联系。

**落点**：`pages/<大类>.md` 里每个主题一节 ——
`## <主题>` → `### 核心结论` / `### 原理与推导` / `### 方法与步骤` / `### 适用条件与边界` / `### 易错点` / `### 相关条目（entry ids）`；
页面级还需要 `## 本类综述`、`## 待裁定冲突`、`## 未覆盖的问题`、`## 已入库条目索引`（索引行格式不变，追加在文末 `<!-- KB:INDEX:BEGIN/END -->` 之间），
并同步 `entry_count` / `updated_at`。完整骨架见 `references/learning.md` §2。

**取用顺序（回答提问时）**：先读 L3 消化层对应小节 → 不够再 `engram_search` 取 L2 → 还缺原文细节就读 L1 并挂 `[src:<L1-id>]` → `engram_assess` 过证据门。

**硬边界**：
- 消化由 **agent 完成，`kb.ps1` 绝不引入 LLM 依赖**（脚本只做文件与登记）。
- 消化产物写 `pages/` 与 L2 **仍必须经用户批准**；`proposed` 时只能在提案里写"消化草案"。
- 你自己的判断（含"这份资料某处错了"）必须标 `by: agent`、`pending_user: true`——**是提案不是终审**。
- 知识页不许整段搬原文；单页超 ~200 行就把细节下沉到 L1/L2。

细节见 `references/learning.md`。

---

## 9. engram 用法速查（L2 写入与检索）

**工具可见性**：若本会话工具清单里**看不到** `engram_*` 工具（`engram_save` / `engram_search` / `engram_facts` / `engram_update` / `engram_assess` / `engram_review_queue` / `engram_report` …），说明工具集是会话启动时固定的 → **告知用户重启 DSH 桌面端或新建会话**，此时不要假装成功，也不要退回用文件模拟 engram。
（实测：`@kenz1117/dsh-engram` 加载后新会话中 `engram_*` 可正常调用；DB 位于 engram 插件的本地 SQLite 库，具体位置由 engram 插件决定。）

**房间路由（`kind` 写英文，`room` 查中文房名）**：

| 内容类型 | `kind`（写入，**英文**） | `room`（检索，**中文房名**） | 备注 |
|---|---|---|---|
| 事实 | `fact` | `事实厅` | 客观陈述：参数、定义、数据 |
| 偏好 | `preference` | `偏好阁` | 用户喜好（"我用 pnpm 不用 npm"） |
| 决策 | `decision` | `决策堂` | 选型结论 + 理由（"选 A 不选 B，因为…"） |
| 事件/资料 | `episode` | `往事廊` | 某次经历、某份资料的要点 |
| 技法流程 | `skill` | `技法坊` | 可复用步骤、方法 |

> 定案依据（`dsh-engram/lib/index.js`）：`:3536-3542` `KIND_ROOMS = { fact:"事实厅", preference:"偏好阁", decision:"决策堂", episode:"往事廊", skill:"技法坊" }`；`:5638` save 的 `kind` 是英文；`:5960` search 的 `room` 原样 `.trim()` 传下去、`:4084` 落到 SQL `AND slot_room IN (...)` —— **room 写英文匹配不上任何房间**。

**⚠️ 默认不要带 `room`（重要）**：房间**每满 9 条就分裂**（`:3549-3563` `assignSlot`）：`决策堂` → `决策堂-2` → `决策堂-3` …。
带 `room` 只能命中一间，会**漏掉溢出房间的记忆**，表现为「库里有却搜不到」。
- **常规做法**：`engram_search(query=..., scope=...)`，**不带 room**，全库检索。
- 仅当 `engram_stats` 房间目录显示该主题**只有一间房**（无 `-2` 后缀）时，才可用中文房名 `room` 收窄。
- 出现 `-2` 后：要么不带 room，要么把该主题所有房间名都试一遍（以 `engram_stats` 实际目录为准，不要硬编码）。

`scope`：跨项目通用知识与用户偏好 → `user`；项目相关 → `project`。

**相似度归并（硬要求）**：engram 在保存前会做相似度告警。**高度相似时必须 `engram_update(id=<旧条目>, content=<新正文>)` 归并，不许造重复条目**。
- 更新后旧条目标「被取代」，取代链保留，可审计。
- 只有"确实是新命题"才 `engram_save`。
- 过时说法替换：新条目取代旧条目，`replaces` 只在 `engram_facts` 里用；engram 记忆条目走 `engram_update`。

**content 格式（固定写法）**：
```
<命题>：<结论>。条件：<适用条件>。来源：<L1-id>。
```
例：`Vite 默认端口：5173。条件：vite >= 2，未在 vite.config 里改 server.port。来源：kb-20261009-0001。`
**没有 `[src:<L1-id>]` 或"来源：kb-…"的条目不得写入。**

**`placard`（门牌）**：4-30 字，唯一、差异化、带日期锚点，如 `2026-10 Vite 端口与代理配置`。禁止与既有门牌近似到无法区分。

**实体与事实链**：需要"某实体在某时点的事实"时用 `engram_facts(entityId=...)`（`asOf` 时点回看）；事实演进用 `replaces` 传旧事实 id，让旧事实软失效，**不要写两条互相矛盾的事实**。

**证据门 `engram_assess`（回答前的自检）**：检索后、作答前必须判定"检索到的内容是否足以回答"。

```
1) 先 engram_search(query=..., scope=...)      # 默认不带 room：房间每 9 条分裂，带了会漏检
   - 有命中时输出末尾会给出 batchId 与每条结果的 ref=…
   - 无命中时没有 batchId → 直接按"库内无此内容"处理（可转联网补齐，标注未审核）
2) engram_assess(batchId="<该批次 id>", sufficient=<true|false>,
                 evidenceRefs=[<最多 8 条，只能取该批次里出现过的 ref>],
                 missing="<缺哪个维度的信息，≤160 字>",
                 nextStrategy="answer | search_keyword | search_room | search_timeline | ask_user | stop")
3) 规则：
   - sufficient=true 时必须带 ≥1 条本批次有效证据，且 nextStrategy 必须为 answer，否则会被判为不足。
   - 证据不足 → sufficient=false，并在 nextStrategy 里给出下一步策略（换关键词 / 换房间 / 查时间线 / 问用户 / 停止）。
   - **不许**在证据不足时凭模型先验作答并伪装成"库里的结论"。
4) 回答里区分三类来源：库内已批准（`[src:<L1-id>]`）/ 库内冲突（显式说明）/ 库外未审核（`[web:<url>]` + "未审核"字样）。
```

详细 schema 与逐字段说明见 `references/engram-usage.md`。

---

## 10. 回答纪律（召回答疑场景）

1. **先读 L3 消化层**：`pages/<大类>.md` 对应主题小节（核心结论 / 原理与推导 / 方法与步骤 / 适用条件与边界 / 易错点），这是最可直接讲的层；再 `engram_search`（**默认不带 `room`**，全库检索；理由见 §9）取 L2 补细节，需要全文时 `engram_examine(ids=[...])`（一次 ≤16 条）；最后 `engram_assess` 过证据门。
2. 每条结论后面挂 `[src:<L1-id>]`，让用户能点回 L1 原文核对。
3. 库内没有 → 明说"库内暂无"，再问用户"要不要我联网补齐？"；**联网结果默认不入库**，必须走提案 + 用户批准。
4. 库内冲突未裁定 → 回答里出现这句固定话术：「库内存在冲突说法，已列入待审队列，请你裁定」+ 列出各方说法与各自 `[src:...]`。
5. 时效敏感内容：查一下 `valid_until`，过期条目不引用；接近过期的加一句"该结论有时效性，建议复核"。
6. 不要一次性倾倒几十条；默认给 3-5 条最相关 + 一句总结，用户要更多再展开。
7. **读题面（图片/截图）：先整体，后局部**。用户贴图（扫描件、手机截图尤其）时，第一步**只做一次整体放大判读**——把整图放大 2× 看全貌、把结构一次性读出来；**禁止**一上来就逐像素 / 逐列游程 / 逐文字框扫描。只有当某个具体标注（刻度值、下标、符号）在整体图里确实读不清时，才裁剪那一小块放大。**同一处最多裁 2 次**；仍读不清 → 在回答里写明"此处读不清"，给出两种可能的解读，然后继续往下做。
8. **止损纪律（专治"想太久"）**：同一个疑点（如"两个字母各指哪条曲线""这个数算 A 还是 B"）最多推演 **2 轮**；第 3 轮必须落地成「结论 + 不确定度 + 备选值」，然后往下走。用户要的是**可用的答案 + 诚实的不确定度**，不是 100% 确定；为同一个不确定点反复取证＝违规。任何需要用户拍板的地方，直接列出来交给用户（这本来就是本系统的设计）。
9. **批量并行**：互不依赖的读取 / 计算放进同一个调用批（多张局部图拼成一张再读、多个独立命令一次跑完）。每一次工具往返＝一次完整模型调用，**往返次数直接等于响应时间**。

---

## 11. 常见故障与兜底

| 现象 | 处理 |
|---|---|
| `engram_*` 工具不可见 | 告知用户重启 DSH 桌面端或新建会话；不要用文件模拟 engram，不要假装写入成功 |
| `kb.config.json` 缺失 | **不影响引擎**（程序不读它）；`kb.cmd` / `kb.ps1` 不在 → 按 §0.0 从技能自带的 `engine/` 复制安装；引擎在但未初始化 → `& "<KB>\kb.cmd" init`（别手搓目录结构） |
| `AuthorizationManager check failed` | 执行策略问题，**与目录位置无关**（旧版文档写的「沙箱 ACL」解释实测已不成立）。默认改调 `kb.cmd`；确需直调 `kb.ps1` 时加 `-ExecutionPolicy Bypass`（或先 `Set-ExecutionPolicy -Scope Process Bypass`）。实测对照见 `references/kb-cli.md` §0 |
| `[磁盘告警] …本次收料继续，但请立即提醒用户清理磁盘` | 剩余空间低于 `storage.warn_free_gb`（当前 20 GB）。**必须在回复里明确告诉用户**并给可清理项；本次收料仍继续（exit=0） |
| `知识库所在磁盘剩余空间不足 … 已拒绝本次收料` | 低于 `storage.block_free_gb`（当前 5 GB）。**立刻停止收料**（exit=1），先告知用户、等指示；不要换成写到别的盘绕过 |
| 用户问「知识库所在盘满了 / 还能存多少」 | 跑 `& "<KB>\kb.cmd" status`，把库根、剩余空间、各层文件数念给用户，并给出可清理项 |
| `kb.cmd` 吐出一堆 `'xxx' is not recognized as an internal or external command` | `kb.cmd` 被写入了非 ASCII 注释；cmd.exe 用 OEM 代码页读 `.cmd`。保持该文件**纯 ASCII** |
| `kb.cmd` 命令报参数错误 | 按报错信息调整，以实测为准；在回答里说明差异，**不改契约** |
| `engram_search` 无命中 | 不是错误。按"库内暂无"如实回答；但先确认**没有传 `room`**（传了英文 kind 或只传了一间房都会假性无命中） |
| **库里有却搜不到** | 几乎都是 `room` 的锅：房间每满 9 条分裂成「决策堂-2」，带 `room` 只命中其中一间。→ **去掉 `room` 全库重查**；或用 `engram_stats` 看实际房间目录后把该主题所有房间都试一遍 |
| 相似度告警 | 改用 `engram_update` 归并；不确定就看 `engram_neighbors(id=...)` 的关联 |
| 用户直接说"直接存，别问了" | **仍然要走提案**。安全阀是硬约束；可以一次性把提案写全、只问一句"批准？" |
| 用户要删资料 | 不删除。移到 `_inbox/_rejected/` 或标记 `rejected`，记日志；确需彻底删除先让用户确认 |
| 网址抓取失败 | 如实报告，可让用户贴正文或换来源；不要把搜索摘要当原文入库 |

---

## 12. references 索引

| 文件 | 内容 |
|---|---|
| `references/contract.md` | **冻结契约 v1（唯一事实来源）**：三层架构（§1）、目录布局（§2）、L1/L2 字段规范（§3/§4）、冲突仲裁算法（§5）、审核工作流（§6）、`kb.ps1` 命令接口（§7）、验收标准（§8）、消化学习层（§9）、知识库定位与磁盘契约（§10） |
| `references/architecture.md` | 三层架构、目录布局、L1 frontmatter 全字段、L3 消化层（五要素结构）写法与反例 |
| `references/review-workflow.md` | 五状态机（`approved` vs `indexed`）、提案 frontmatter 全字段集、批准后「脚本已做 / agent 接着做」分工、驳回/要改、log.jsonl 实际字段、安全阀检查点 |
| `references/arbitration.md` | 八步仲裁可执行伪码（含第 ④ 步**正误推理**）、`verdict` 语义、source_rank 数值表、resolved/判错/conflict 输出格式、话术 |
| `references/learning.md` | **消化学习层**：五要素（概念/原理/步骤/边界/易错点）、知识页结构、产出时机与硬边界、消化层优先的取用顺序、自检 |
| `references/engram-usage.md` | 全部相关 `engram_*` 工具 schema、room/scope 路由、content 格式、相似度归并、`engram_assess` 证据门 |
| `references/kb-cli.md` | `kb.cmd`/`kb.ps1` 各命令用法（含 `status` 磁盘闸门）、三种调用方式的实测结论、KB 根目录定位（引擎自定位；`kb.config.json` 的 `root` 不是权威）、与契约 §7 的对应关系、故障排查 |

---

## 13. 回答前自检清单（每次动手前跑一遍）

- [ ] **收料/批量写入/导入大文件之前，我跑过 `& "<KB>\kb.cmd" status` 吗？**（有 `[磁盘告警]` 或剩余 < 20 GB → 我有没有在回复里明确告诉用户并给可清理项？低于 5 GB → 我有没有停下收料？）
- [ ] 我这次要写的地方，是否只限于该状态允许的目录？（`proposed` 时**只**能碰 `_inbox/`、`_review/queue/`、`_system/log.jsonl`）
- [ ] 喂料时我是不是先跑了 `& "<KB>\kb.cmd" add -Path`？（手搓 `_inbox/` 文件或自算 id → 违规，丢了查重与 id 分配）
- [ ] 用户批准后，我有没有**自己先写一份 L1**？（写了 → 脚本会静默生成 `…-2.md`，L1 出现两张卡；L1 永远由 `approve` 落盘）
- [ ] 我有没有在用户批准前调用任何 `engram_*` 写入工具？（有 → 违规，停手）
- [ ] 我要写的 L2 条目正文里有没有 `[src:<L1-id>]` / "来源：kb-…"？
- [ ] 是不是已有高度相似条目？→ 该用 `engram_update` 归并。
- [ ] 我引用了付费服务吗？（Hindsight 云 / 付费嵌入 API → 禁止）
- [ ] 我引用库内条目的回答里，每条都带 `[src:...]` 了吗？
- [ ] 有冲突时我是不是擅自选边了？（分不出胜负 → `conflict` + 待审队列，绝不选边）
- [ ] 我有没有把 L1 原文整段搬进 L3？（搬了 → 违规，L3 只放综述与索引）
- [ ] 联网内容我标注"未审核"了吗？它有没有被当成裁定依据？（不许）
- [ ] 我往 `_system/log.jsonl` 追加的那行，用的是 `target` / `note` 吗？（写成 `id` / `detail` → `kb.cmd log` 的 id 列与详情列全空）
- [ ] 收尾做了吗？（`_review/approved/<id>.md` 的 status 改 `indexed` + 补一行 `l2-saved`；**L1 的 status 保持 `approved`**）
- [ ] 有冲突时我是不是**先做了可检验的正误推理**（内部自洽 / 公认基准 / 库内相容；理由写成推导、反例、量纲或定义冲突），而不是靠"更常见 / 更符合直觉 / 感觉更权威"下判断？判错之后有没有**显式告知用户**并建待审记录（绝不静默丢弃）？
- [ ] 我有没有在用户批准前偷写 `pages/` 或 engram？（有 → 违规停手；`proposed` 时只能在提案里写"消化草案"）
- [ ] 消化产物五要素齐了吗？缺的项写明"原文未涉及"了吗？我自己的判断标了 `by: agent` + `pending_user: true` 吗？
- [ ] 用户贴了图/截图时，我是不是**先把整图放大看了一次**，而不是直接开始逐像素扫描或逐个裁剪？
- [ ] 有没有哪个疑点我已经取证超过 2 轮还没落地？（有 → 立刻收成「结论 + 不确定度 + 备选值」，继续往下做）
- [ ] 互不依赖的调用我合并成一批发出了吗？（每一次工具往返就是一次完整的响应延迟）
