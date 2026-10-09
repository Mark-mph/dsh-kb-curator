# 审核工作流（五状态 + 两终态）

> 依据：`references/contract.md` §6。本文是执行细则。
> **分工铁律**：`kb.cmd approve` 已经做完的事（L1 落盘、提案归档、写日志），agent **绝对不要重做**——重做会让 L1 出现两张卡。

## 1. 状态机

```
inbox ──agent 提案──> proposed ──用户批准──> approved ──agent 写 L2/L3──> indexed
                        │                     ▲
                        ├──用户驳回──> rejected
                        └──用户要改──> needs_edit ──agent 改完──> proposed
```

| 状态 | 触发者 | 含义 | 允许的写盘范围 |
|---|---|---|---|
| `inbox` | 用户喂料 | 原文已收到，未处理 | `_inbox/`、`_system/log.jsonl` |
| `proposed` | agent | 提案已生成，等用户裁决 | `_review/queue/`、`_inbox/`、`_system/log.jsonl` |
| `needs_edit` | 用户 | 要求修改提案 | 同 `proposed`，改完回 `proposed` |
| `rejected` | 用户 | 驳回 | `_review/rejected/`、`_inbox/_rejected/`、`_system/log.jsonl` |
| `approved` | `kb.cmd approve` | 用户已批准：**L1 已落盘 + 提案已归档**（脚本做完），等 agent 写 L2/L3 | `_system/log.jsonl`（脚本写的）；L2/L3 仍待 agent 做 |
| `indexed` | agent | agent 已写完 L2 + L3，归档提案的 status 已改 `indexed` | `pages/<大类>.md`、`_review/approved/<id>.md`、`_system/log.jsonl` |

> `approved` 与 `indexed` 落在**不同的文件**上：L1 原文卡的 `status` 永远是 `approved`（脚本写的，**勿手改**）；
> `_review/approved/<id>.md`（归档提案）的 `status` 才由 `approved` 推进到 `indexed`。

## 2. 安全阀（契约 §6 明文，硬约束）

> **`proposed` 状态下 agent 不得写 L1 / L2 / L3；任何绕过均为违规。**

- 没有"先写进去等批准"这种临时状态。engram 里**没有草稿区**。
- 未批准的提案正文只活在 `_review/queue/<id>.md` 里。
- **也不要自己写 `library/`（L1）**：L1 落盘是 `kb.cmd approve` 的活；抢先写会让 `approve` 静默生成 `…-2.md` 重复卡（见 §4）。
- 如果用户说"别问了直接存" → 仍然只写提案，然后只问一句"批准？"，等答复再入库。
- 违规自检：写 L2 前问自己"这个 id 的状态是 approved 吗？" 不是 → 停手。

## 3. 提案文件格式（`_review/queue/<id>.md`）

**格式以 `<KB>/_templates/review-proposal.md` 为准，本文不重复定义字段含义。**

必含 **6 项内容**（契约 §6 逐条列举，缺一不可）：原文摘要 / 建议分类 / 建议优先级 / 置信度 /
**将要写入 engram 的条目正文（含 `[src:<id>]`）** / 将要更新的知识页 diff。

**⚠️ 硬性要求：`approve` 只读 frontmatter。** `kb.ps1` 的 `Cmd-Approve` 用 `Pick $fm '<字段>'` 从 **frontmatter**
取 `category` / `subcategory` / `title` / `content_hash` / `inbox_path` / `l2_content` / `l2_kind` / `l2_scope` /
`source_type` / `source_url` / `fetched_at` / `added_at` / `priority` / `confidence` / `valid_from` / `valid_until` /
`supersedes` / `tags` / `proposition_key` / `origin_path`。
把这些字段写在**正文**里等于没写。**当前版本的错误形式是"静默降级"，不是报错**（`Cmd-Approve` 带兜底）：
`inbox_path` 为空 → 脚本按 id 在 `_inbox/` 里模糊找副本，找得到就继续（只有完全找不到才 `Fail` exit=1）；
缺 `category` → 静默落 `未分类/通用/`；缺 `title` → 文件名退化成 `<日期>-<id>.md`；
缺 `l2_content` → 脚本打印给 agent 的 `engram_save(content="")` 是**空字符串**（L2 会写进一条空内容）。
另外 `list-queue` 会对缺 `category` / `inbox_path` 的提案打 `[警告]`。
（以上三者均已实测：一份把字段全写在正文里的提案 approve 后 exit=0，但落进 `未分类/通用/2026-10-09-kb-…-0002.md`、
L2 正文为空、只靠 list-queue 的警告提醒——所以字段必须写全，别指望报错救你。）

````markdown
---
id: kb-20261009-0001
title: "Vite 构建工具默认端口说明"
category: 技术工程
subcategory: 前端
source_type: user_text
source_url: ""
fetched_at: ""
added_at: 2026-10-09T12:00:00+08:00
content_hash: "435f1bb7fa0505a0fff3b5d585a9afe2f793cae9030aa15e72e500155abb17a5"
status: proposed
priority: 3
confidence: 0.8
valid_from: ""
valid_until: ""
supersedes: []
tags: [构建工具, 前端]
proposition_key: "前端/构建工具/vite-默认端口"
source_rank: 100
inbox_path: "_inbox/kb-20261009-0001-vite-构建工具默认端口说明.md"
origin_path: "D:\dl\vite.md"
l2_kind: fact
l2_scope: user
l2_content: "Vite 默认端口：5173。条件：vite >= 2 且未改 server.port。来源：kb-20261009-0001。 [src:kb-20261009-0001]"
---

# 待审提案 kb-20261009-0001

## 1. 原文摘要
（3-5 行，说清这份资料讲了什么；不是原文正文）

## 2. 建议分类
- 大类：技术工程 / 子类：前端
- 依据：标题与正文均命中 taxonomy「技术工程/前端」触发词（vite、构建、打包）。
- proposition_key：前端/构建工具/vite-默认端口

## 3. 建议优先级与置信度
- priority：3（1-5，5 最高）
- confidence：0.8（0-1）
- source_rank：100（user_provided=100 / user_approved_web=60 / unapproved_web=20）
- 时效：valid_from= / valid_until=（空 = 长期有效）

## 4. 将要写入 engram 的条目正文（L2，用户批准后原样写入）
- kind：fact（**英文**：fact / preference / decision / episode / skill）
- ⚠️ **不要传 `room`**：`room` 只认中文房名（`事实厅` 等），传英文匹配不上任何房间
- scope：user
- content：Vite 默认端口：5173。条件：vite >= 2 且未改 server.port。来源：kb-20261009-0001。 [src:kb-20261009-0001]

## 5. 将要更新的知识页 diff（L3）
文件: pages/技术工程.md
```diff
 ## 构建工具
+- Vite 默认端口 5173；改端口改 `server.port`。[src:kb-20261009-0001]
```

## 6. 待用户裁决
请回复：**批准 / 驳回（给理由） / 要改（说明改什么）**

## 7. 原文位置
- L0 副本：`_inbox/kb-20261009-0001-vite-构建工具默认端口说明.md`
- 用户原文件：`D:\dl\vite.md`（**始终不动**，系统只读副本）
- 落盘目标（批准后）：`library/技术工程/前端/2026-10-09-vite-构建工具默认端口说明.md`
````

**注意**：
- `l2_content` 必须是**最终会写进 engram 的完整正文**——用户批准的就是这句话，不是"一些要点"。
- 最容易漏的三个 frontmatter 字段：`category`（漏 → 静默归 未分类）、`inbox_path`（漏 → 脚本按 id 兜底找 L0 副本，找不到才失败）、`l2_*` 三个（漏 → 批准后不知道该写什么进 L2，脚本会打印空的 `content=""`）。
- `id` / `content_hash` / `inbox_path` / `added_at` 直接取自 `kb.cmd add` 生成的 `_inbox/<id>.*.meta.md`，**不要自己编**。
- `proposition_key` 相同 = 同一命题的不同说法（仲裁按它聚类），不是重复资料。

## 4. 批准后：谁做什么（顺序固定）

`& "<KB>\kb.cmd" approve <id>` **已经完成**下面三件（脚本自己写日志，你不要重做）：

```
① L1 落盘（kb.ps1 做）—— 不要再自己写一份！
   <KB>/library/<大类>/<子类>/<yyyy-mm-dd>-<slug>.md
   （slug 由提案的 `title` 生成，与提案文件名无关；实际路径以 approve 打印的 `[① L1 落盘]` 一行 + log 里的 l1 字段为准）
   frontmatter 由脚本写全契约 §3 字段，status: approved
   原文取自 _inbox/ 的 L0 副本，逐字写入（不改写、不摘要）
② 提案归档（kb.ps1 做）
   _review/queue/<id>.md → _review/approved/<id>.md（作为审核痕迹）
③ 写日志（kb.ps1 做）
   _system/log.jsonl 追加 action=approve、target=<id>、by=user、l2_pending=true
   （只有显式加 -UpdatePage 时脚本才机械追加一行索引到 pages/；默认不动 L3）
```

**agent 必须接着做的三步（缺一步都不算"已入库"）**：

```
④ L2 写入（agent 做）
   相似度检查（先 engram_search 同命题，默认不带 room）
     ├─ 已有高度相似条目 → engram_update(id=<旧id>, content=<新正文>) 归并
     └─ 确为新命题     → engram_save(content=<l2_content>, kind=<英文 kind：fact|preference|decision|episode|skill>, scope=<l2_scope>, placard=<门牌>)
   正文必须含 "来源：<L1-id>" / [src:<L1-id>]

⑤ L3 更新（agent 做）
   编辑 <KB>/pages/<大类>.md：本类综述 3-8 句 + 「已入库条目索引」追加一行 + [src:<L1-id>]
   只加结论与索引，禁止粘贴原文

⑥ 收尾（agent 做，两步）
   - 把归档提案 _review/approved/<id>.md 的 status 改成 indexed；
     # 注意：L1 原文卡的 status 保持 approved（脚本落定），**勿手改**
   - 追加一行日志（字段用 target/note，见 §6）：
     {"ts":"<ISO8601>","actor":"agent","action":"l2-saved","target":"<id>","note":"L2/L3 已写入，入库完成","by":"agent","id":"<id>","l2_pending":false}
```

**⚠️ 绝不要自己先写 L1。** `Cmd-Approve` 落盘遇同名会走防覆盖分支（`while (Test-Path) { … '-' + $n }`），
**静默生成 `…-2.md`**：同一份资料在 L1 出现两张卡，一张是脚本凭 L0 副本写的、一张是你手写的，来源与
`added_at` 都对不齐（已实测复现）。
固定顺序永远是：**用户批准 → 跑 `kb.cmd approve` → agent 写 L2 → agent 写 L3 → 改归档提案状态为 `indexed`**。

## 5. 驳回与要改

**驳回**：
```
1) `& "<KB>\kb.cmd" reject <id> -Reason "<用户原话>"`：提案 → _review/rejected/<id>.md，
   L0 副本 → _inbox/_rejected/，脚本写 action=reject 日志（不删除任何文件）
2) 回话：确认已驳回 + 归档路径
```

**要改**：
```
1) `& "<KB>\kb.cmd" show <id>` 看现行提案，状态 → needs_edit
2) 按用户意见改提案 frontmatter（分类 / 优先级 / 置信度 / l2_content / L3 diff），**frontmatter 缺字段 approve 会失败**
3) 状态改回 proposed，重新贴给用户确认
4) 回话时明确"已按你说的改了什么"
```

## 6. log.jsonl 格式（追加式，一行一事件）

**字段名以 `kb.ps1` 的 `Write-KbLog` 为准**；`Cmd-Log` 只渲染 `ts` / `action` / `target` / `note` 四列
（`Write-Info ('{0}  {1,-12} {2,-24} {3}' -f $o.ts, $o.action, $o.target, $o.note)`）。

| 字段 | 含义 |
|---|---|
| `ts` | ISO8601 时间 |
| `actor` | `kb.ps1` / `agent` / `user` |
| `action` | `add` / `propose` / `approve` / `reject` / `edit` / `show` / `page` / `l2-saved` |
| `target` | **放 id**（`kb.cmd log` 的第 3 列） |
| `note` | **中文短句详情**（`kb.cmd log` 的第 4 列） |
| `by` | `user` / `agent` |
| `id` | 同 `target`（冗余，便于以后按 id 检索） |
| `l2_pending` | 布尔：L2 是否还没写 |

**⚠️ 不要写 `detail` 字段**：旧文档的 `{"id":…,"detail":…}` 格式会让 `kb.cmd log` 的 **id 列与详情列全空**
（`ConvertFrom-Json` 后没有 `target`/`note` 键，`-f` 渲染成空白，已实测）。脚本打印的 `l2-saved` 简化行也缺
`ts`/`target`/`note`，照下面完整字段写。

```json
{"ts":"2026-10-09T12:00:00+08:00","actor":"agent","action":"add","target":"kb-20261009-0001","note":"kb.cmd add 收料入 _inbox","by":"agent","id":"kb-20261009-0001","l2_pending":false}
{"ts":"2026-10-09T12:01:00+08:00","actor":"agent","action":"propose","target":"kb-20261009-0001","note":"提案入 queue，建议分类 技术工程/前端","by":"agent","id":"kb-20261009-0001","l2_pending":true}
{"ts":"2026-10-09T12:14:54+08:00","actor":"kb.ps1","action":"approve","target":"kb-20261009-0001","note":"l1=library\\技术工程\\前端\\2026-10-09-vite-构建工具默认端口说明.md;archive=_review/approved/kb-20261009-0001.md;l2_pending=true;l3_page_pending=pages/技术工程.md","by":"user","id":"kb-20261009-0001","l2_pending":true}
{"ts":"2026-10-09T12:16:00+08:00","actor":"agent","action":"l2-saved","target":"kb-20261009-0001","note":"L2 engram_save(kind=fact,scope=user) + L3 pages/技术工程.md 已更新，归档提案 status=indexed","by":"agent","id":"kb-20261009-0001","l2_pending":false}
{"ts":"2026-10-09T12:20:00+08:00","actor":"kb.ps1","action":"reject","target":"kb-20261009-0002","note":"理由：来源不可靠","by":"user","id":"kb-20261009-0002","l2_pending":false}
```

**只追加，不重写、不删行。**

## 7. 用户视角完整往返（契约 §8 验收第 7 条）

```
用户：喂一份资料（给文件路径 / 贴文本 / 给网址）
你  ：① & "<KB>\kb.cmd" add -Path <文件>      # 脚本分配 id + content_hash 查重 + 生成 .meta.md
      ② 读 _inbox/<id>.*.meta.md 与 L0 原文副本
      ③ 写 _review/queue/<id>.md（status: proposed，frontmatter 字段集照 _templates/review-proposal.md）
      ④ 回复"建议分类 X，优先级 N，将入库条目：…，批准 / 驳回 / 要改？"
用户：批准
你  ：⑤ & "<KB>\kb.cmd" approve <id>          # 脚本落 L1 + 归档提案 + 写日志（这三件不重做）
      ⑥ engram_save(...) / engram_update(...)  # L2
      ⑦ 更新 pages/<大类>.md（综述 + 索引行）  # L3
      ⑧ 归档提案 status 改 indexed + 补一行 l2-saved 日志
      ⑨ 回复"已入库：L1 <路径>、L2 <房名>、L3 <页面>；日志已记录"
用户：知识库里 Vite 默认端口是多少？
你  ：engram_search（默认不带 room）→ engram_assess(sufficient) → "5173 [src:kb-xxxx]（条件：未改 server.port）"
```

任何一步失败（脚本报错 / 工具不可用）→ **如实告知**，不要声称成功。
已做一半时明确说"⑤ 已完成（L1 与归档都好了），⑥ 失败，原因是…"。

## 8. 审核相关自检

- [ ] 提案 6 项内容齐全，且 `category` / `inbox_path` / `l2_kind` / `l2_scope` / `l2_content` 都写在 **frontmatter** 里（写在正文里 `approve` 读不到）。
- [ ] 第 4 项是可直接写入 engram 的完整正文，且含 `[src:<id>]`。
- [ ] 用户批准前，我没有调用任何 `engram_*` 写入工具，也没有改 `pages/`、没有写 `library/`。
- [ ] 批准后我**先跑了 `kb.cmd approve`**，而没有自己手写 L1（手写 → 重复 `-2.md`）。
- [ ] `approve` 之后我补做了 L2 + L3，把归档提案 status 改成 `indexed`，并补了 `l2-saved` 日志（字段用 `target`/`note`）。
- [ ] 驳回时保留了用户理由原文，原文移到 `_rejected/` 而非删除。
- [ ] `supersedes` / `engram_update` 的取代关系在提案里已说明。
