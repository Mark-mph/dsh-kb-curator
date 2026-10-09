# engram 用法（L2 检索层）

> 依据：`references/contract.md` §4 + 参考环境 `@kenz1117/dsh-engram` 实际工具 schema。
> engram DB：engram 插件的本地 SQLite 库（具体位置由 engram 插件决定）。
> 嵌入模型：`Xenova/bge-small-zh-v1.5`，512 维 q8 量化，纯 CPU 离线，**免费**。

## 0. 工具可见性（重要）

若本会话工具清单里**看不到** `engram_*` 系列工具 → 工具集是**会话启动时固定**的，
**告知用户：重启 DSH 桌面端或新建会话**。
此时**不要**用本地文件模拟 engram，**不要**假装写入成功，**不要**把条目记在聊天里充数。

**实测记录（参考环境）**：`@kenz1117/dsh-engram` 启用后，宿主加载成功（`include:dsh-engram` status=schema），
新会话中 `engram_*` 工具**可正常调用**（`engram_stats`、`engram_search` 均实测返回正常）。
只读查询返回空库属正常（`总数 0`），不是故障。

## 1. 房间路由（写 `kind` 用英文，查 `room` 用中文房名）

**已从源码定案（`dsh-engram/lib/index.js`）**：

- `:3536-3542` `const KIND_ROOMS = { fact: "事实厅", preference: "偏好阁", decision: "决策堂", episode: "往事廊", skill: "技法坊" };`
- `:3549-3563` `assignSlot(kind, occupancy)`：`const base = KIND_ROOMS[kind]` → **落库的房间名就是中文**；且**每间满 9 条就开新房**：`决策堂-2`、`决策堂-3` …
- `:5638` **`engram_save` 的 `kind` 是英文**（描述：`kind：fact 事实 / preference 偏好 / decision 决策 / episode 经历 / skill 方法`）。
- `:5960` **`engram_search` 的 `room` 参数原样 `.trim()` 传下去**；`:4084` 落到 SQL `AND slot_room IN (...)` —— 所以 `room` 必须写**中文房名**，写英文匹配不上任何房间。

### kind ↔ 房名 对照表（互查用）

| 内容类型 | `kind`（写入用，英文） | `room`（检索用，中文房名） | 典型例子 |
|---|---|---|---|
| 事实 | `fact` | `事实厅` | 参数、定义、数据、默认值 |
| 偏好 | `preference` | `偏好阁` | "用 pnpm 不用 npm"、"回答要简短" |
| 决策 | `decision` | `决策堂` | "选 A 不选 B，因为 Z" |
| 事件 / 资料 | `episode` | `往事廊` | 某次经历、某份资料的要点 |
| 技法流程 | `skill` | `技法坊` | 可复用步骤、方法、checklist |

### ⚠️ 运营后果：默认不要用 `room`（最重要的一条）

房间**每满 9 条就分裂**（`决策堂` → `决策堂-2` → `决策堂-3` …）。
因此 `room` 只能**精确命中一间房**，用它当主检索方式会**漏掉溢出房间里的记忆** ——
表现为"库里有却搜不到"。

**规则**：
1. **默认全库检索**：`engram_search(query=..., scope=...)`，**不带 `room`**。这是常规做法。
2. 只有在**两个条件同时满足**时才用 `room` 收窄：
   - `engram_stats(scope="all")` 的房间目录显示该主题**只有一间房**（没有 `-2` / `-3` 后缀）；
   - 且你想在明确知道类型时快速收窄（如查用户偏好 → `偏好阁`）。
3. 一旦目录里出现 `决策堂-2`，要么**不带 room 全库查**，要么把该主题的所有房间名都列进检索（溢出房间名以 `engram_stats` 实际目录为准，不要把房名硬编码在脚本里）。
4. `engram_assess` 的 `nextStrategy="search_room"` 只在"确认该主题单间房"时才用；否则优先 `search_keyword`。

**注意**：`engram_save` 的 `kind` 永远是英文；只有 `engram_search` 的 `room` 用中文房名。两者不要混。

## 2. scope 选择

- `user`：跨项目通用知识、用户偏好、用户级决策 → 任何项目都该召回。
- `project`：与特定项目强绑定的事实/决策（如"本项目统一用 pnpm"） → 只对该项目有效。
- `shared`：本机共享库；**默认不用**，除非用户明确要求共享给多项目。
- 检索时 `scope="all"`（默认）能同时看两库；写库时**必须显式选 user 或 project**，不要靠默认。

## 3. 写入：`engram_save`

```
engram_save(
  content    = "<命题>：<结论>。条件：<适用条件>。来源：<L1-id>。",   # 必填
  kind       = "fact|preference|decision|episode|skill",             # 必填
  scope      = "user|project|shared",                                 # 默认 project
  importance = 0.5,                                                   # 0-1，可选
  placard    = "<4-30 字门牌，唯一·差异化·带日期锚点>",               # 可选但强烈建议
  entities   = [{name:"Vite", kind:"tool", aliases:["vite"]}]         # 可选，实体检索用
)
```
批量：`items=[{content, kind, importance?, entities?}, ...]`（最多 10 条，单条失败不影响其余）。
单条与批量二选一。

**content 硬要求**：必须含来源 `[src:<L1-id>]` 或 `来源：kb-…`（契约 §4）。
**placard 纪律**：4-30 字，唯一、差异化、带日期锚点；禁止与既有门牌近似到无法区分。例：`2026-10 Vite 端口与代理配置`。

## 4. 相似度归并（硬要求，别造重复）

engram 每次保存前会做**相似度告警**。
- 出现"高度相似"告警 → **必须改用 `engram_update` 归并**，不许再造一条。
- `engram_update(id=<旧条目id>, content=<新正文>, scope=..., kind=..., placard=...)`
  → 写入新条目并把旧条目标记"被取代"，**取代链保留，可审计**。
- 不确定是不是同一命题 → `engram_neighbors(id=<旧条目id>, depth=1..3)` 看关联，或 `engram_review(id=...)` 看来源与取代链。
- 判定标准：`proposition_key` 相同且结论不同 → 归并（后者取代前者）；命题不同 → 新条目。

**过时说法替换流程**：新资料照喂 → 用户批准 → `engram_update` 取代旧条目 → L1 的 `supersedes` 填旧 id → L3 页面同步改。

## 5. 检索：`engram_search`

```
engram_search(
  query = "关键词自然语言",           # 必填
  room  = "事实厅|偏好阁|决策堂|往事廊|技法坊（中文房名；默认不传）",  # 可选，只在指定房间检索
  scope = "user|project|shared|all",  # 默认 all
  limit = 8,                          # 默认 8
  asOf  = "2026-03-01"                # 可选：时点回看，附各实体该时点仍有效的事实快照
)
```

- 混合检索：语义 + 关键词。
- 结果行尾给出 `id`，供 `engram_examine` / `engram_update` / `engram_report` 引用。
- **有命中时输出末尾会给出 `batchId` 与该批次的 `ref=…`**，这是证据门 `engram_assess` 的输入。
- **无命中时不产生 `batchId`**（实测：空库查询只返回"无命中"）→ 直接按"库内暂无"处理。

检索策略：**默认不带 `room`，先全库检索**（房间每 9 条分裂，按房间查会漏）。
只有在 `engram_stats` 房间目录显示该主题**只有一间房**时，才用中文房名 `room` 收窄。
关键词比房间更可靠 —— 拿不准就换关键词，不要靠房间。

## 6. 证据门：`engram_assess`（检索后、作答前必过）

```
engram_assess(
  batchId      = "<engram_search 输出末尾的批次 id，如 batch-3>",  # 必填
  sufficient   = true|false,                                        # 必填
  evidenceRefs = ["<最多 8 条，只能取该批次输出里的 ref=…>"],
  missing      = "<缺哪个维度的信息，≤160 字>",
  nextStrategy = "answer|search_keyword|search_room|search_timeline|ask_user|stop"
)
```

代码强制校验规则：
- `sufficient=true` 需**同时**满足：① 你声称充足 ② **至少一条属于本批次的有效证据** ③ `nextStrategy="answer"`。
  否则判为不足，并把策略改回"继续检索"。
- `evidenceRefs` 里**不属于该批次的 ref 会被拒绝**，并在拒绝明细里列出。
- 判词与拒绝明细写入审计日志。

**用法纪律**：
- 证据不足 → `sufficient=false`，在 `missing` 写清缺什么，在 `nextStrategy` 给下一步（换关键词 / 换房间 / 查时间线 / 问用户 / 停止）。
- **不许**证据不足时凭模型先验作答、再伪装成"库里的结论"。
- 库内没有 → `nextStrategy="ask_user"`（问是否联网补齐）或 `"search_keyword"`（换词重查），**不是** `answer`。

## 7. 其它常用工具

| 工具 | 用途 | 关键参数 |
|---|---|---|
| `engram_examine` | 按 id 批量拉完整铭牌（内容 + 房间 + 状态 + 边） | `ids`（建议 ≤16，超出按顺序取前 N） |
| `engram_facts` | 实体事实链查询 / 写入 | 查：`entity` 或 `entityId`、`asOf`、`includeInvalid`；写：`facts=[{entity\|entityId, content, replaces?}]` |
| `engram_neighbors` | 走廊漫步 1-3 跳关联 | `id`、`depth`（默认 1，最大 3） |
| `engram_review` | 审计一条：内容/来源/取代链/矛盾/日志 | `id`、`scope` |
| `engram_review_queue` | 今日待回忆队列（间隔重复） | `scope`、`limit` |
| `engram_report` | 回报效果：`outcome=success\|failure` 或复习自评 `grade=0..5` | `id`、`scope` |
| `engram_timeline` | 按时间/主题浏览 | `since`、`until`、`topic`、`order=time\|tour` |
| `engram_episode_timeline` | 情景记忆时间线，`around` 切邻近扩展 | `around`、`windowMinutes` |
| `engram_tour` | 巡游路线 | `mode=fixed\|thematic`、`query`、`maxStops` |
| `engram_stats` | 库统计 + **房间目录**（看有没有 `-2` 溢出房间，决定能不能用 `room`） | `scope` |
| `engram_distill` | 同主题记忆簇合并提炼（旧条归档、supersedes 链保留） | `scope` |
| `engram_forget` | 软删（须留"为什么关/影响谁/还有用吗"墓志铭） | `id`、`reason`、`affects`、`stillUseful` |
| `engram_update` | 修正并取代旧条目（**归并首选**） | `id`、`content` |
| `engram_profile_edit` | 编辑会话开始注入的用户画像 curated block | `action=view\|edit\|rollback` |
| `engram_export` | 导出记忆库（md/json/markdown-mirror） | `format`、`scope`、`redactedView` |

**事实修正用 `replaces`**：修正过时事实时传 `replaces=<旧事实 id>`，旧事实软失效、新事实接棒，历史链保留。
**不要**反复保存互相矛盾的事实——用取代链表达演变。

## 8. 与 L1/L3 的接口

```
用户批准
   └─> engram_save / engram_update（L2）
         └─> content 里的 "来源：kb-20261009-0001" 指向 L1 文件
               └─> L3 pages/<大类>.md 里追加 - 一句话 [src:kb-20261009-0001]
```

- 检索召回后回答：每条结论挂 `[src:<L1-id>]`；用户可 `read` L1 原文核对。
- L2 条目的可信度上限 = 其 L1 的来源类型（user_provided / user_approved_web / unapproved_web）。

## 9. engram 自检

- [ ] 写入前查过相似度？高度相似用了 `engram_update`？
- [ ] content 里有 `[src:<L1-id>]` / "来源：kb-…"？
- [ ] `kind` 是**英文**（fact/preference/decision/episode/skill）？
- [ ] 如果传了 `room`，它是**中文房名**，且 `engram_stats` 确认该主题只有一间房（无 `-2` 溢出）？**默认应该不传 room**。
- [ ] `scope` 选对（通用→user、项目→project）？
- [ ] `placard` 唯一、有日期锚点、不与既有近似？
- [ ] 作答前跑过 `engram_assess`，且 `evidenceRefs` 都来自本批次？
- [ ] **写入发生在用户批准之后**？（安全阀）
