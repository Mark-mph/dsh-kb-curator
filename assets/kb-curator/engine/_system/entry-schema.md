# 字段规范 entry-schema（冻结契约 v1 §3 + §4）

> L1 原文卡 = `library/<大类>/<子类>/<yyyy-mm-dd>-<slug>.md`
> L2 记忆条目 = 写入 engram 的一条 content（无文件 frontmatter，格式见本文 §2）
> L3 知识页 = `pages/<大类>.md`（模板见 `_templates/knowledge-page.md`）

---

## 1. L1 原文卡 frontmatter（YAML，字段名固定，不得改名）

```yaml
---
id: kb-20261009-0001              # 固定格式 kb-<yyyymmdd>-<4位序号>，全局唯一
title: "标题"
category: 技术工程                 # 必须是 taxonomy.yml 里的大类
subcategory: 前端                  # 可为空，空则该类别的默认子类
source_type: user_file            # user_file | user_text | web
source_url: ""                    # source_type=web 时必填
fetched_at: ""                    # source_type=web 时必填，ISO8601
added_at: 2026-10-09T12:00:00+08:00
content_hash: "<sha256 原文>"      # 用于去重与版本比对
status: inbox                     # inbox | proposed | approved | rejected | needs_edit | indexed
priority: 3                       # 1-5，5 最高，用户可调
confidence: 0.8                   # 0-1，agent 提案、用户可改
valid_from: ""                    # 时效起点，可空
valid_until: ""                   # 时效终点，空=长期有效
supersedes: []                    # 被本条取代的旧条目 id 列表
tags: []
proposition_key: ""               # 命题键：同一命题的条目共用一个 key，仲裁按它聚类
---
```

字段逐条说明：

| 字段 | 必填 | 取值 / 生成规则 |
|---|---|---|
| `id` | 是 | `kb-<yyyymmdd>-<4位序号>`，序号按当日已有 id 递增；kb.ps1 `init`/`add` 自动分配 |
| `title` | 是 | 资料标题；缺省取正文首个 `# 标题`，再缺省取原文件名 |
| `category` | 是 | 必须是 `taxonomy.yml` 中的大类；不确定时用 `未分类` |
| `subcategory` | 否 | `taxonomy.yml` 中该大类的子类；空则用 `通用` |
| `source_type` | 是 | `user_file`（用户给的文件）/ `user_text`（用户口述粘贴）/ `web`（联网抓取） |
| `source_url` | web 必填 | 原文 URL |
| `fetched_at` | web 必填 | 抓取时刻，ISO8601 |
| `added_at` | 是 | 进入系统的时刻，ISO8601（带时区，如 `+08:00`） |
| `content_hash` | 是 | 原文正文的 sha256 十六进制小写；用于去重与版本比对 |
| `status` | 是 | 见 §3 五状态；新建资料从 `inbox` 开始 |
| `priority` | 是 | 1-5 整数，5 最高，默认 3；规则见 `priority.yml` |
| `confidence` | 是 | 0-1 浮点，默认 0.8；规则见 `priority.yml` |
| `valid_from` | 否 | 时效起点，可空 |
| `valid_until` | 否 | 时效终点，**空 = 长期有效**；过期条目在仲裁第 3 步被剔除 |
| `supersedes` | 否 | 本条取代的旧条目 id 数组；新说法优先用「新增 + supersedes」而不是改写旧卡 |
| `tags` | 否 | 自由标签数组 |
| `proposition_key` | 是（建议） | **仲裁核心**，形如 `前端/构建工具/vite-默认端口`；同一命题的多个说法共用一个 key，未填时默认 `<category>/<subcategory>/<slug>` |

**去重**：`add` 时若 `library/` 中已有相同 `content_hash`，必须提示「疑似重复」并给出已有 `id`，不得静默重复入库。

---

## 2. L2 记忆条目（写入 engram）

### 2.1 条目性质 → kind → 自动房名（**不要手动传 `room`**）

`engram_save` 只收英文 `kind`；engram 会按 `KIND_ROOMS` 自动把条目排桩到中文房名，
**每间房满 9 条就分裂出 `-2` 新房**（`决策堂-2`…）。所以：

| 条目性质 | `kind`（写这个，英文） | engram 自动落的房名（不要手填） |
|---|---|---|
| 事实 | `fact` | `事实厅` |
| 偏好 | `preference` | `偏好阁` |
| 决策 | `decision` | `决策堂` |
| 事件 / 资料 | `episode` | `往事廊` |
| 技法流程 | `skill` | `技法坊` |

> ⚠️ 常见错法：把 `room` 当成 `kind` 的同义词、传 `room="fact"`。`engram_search` 的 `room` 只认**中文房名**
> （源码落到 `slot_room IN (...)`），传英文匹配不到任何房间，表现为「库里明明有却搜不到」。
> 因此**知识库一律不带 `room` 检索（全库查）**；只有 `engram_stats` 显示该主题确实只有一间房时，才可收窄。

### 2.2 硬性要求

1. **每条 content 必须带来源标记 `[src:<L1-id>]`**，否则视为不合格条目，禁止保存。
2. 保存前 engram 会做相似度告警：**高度相似时必须改用 `engram_update` 归并**，不许制造重复条目。
3. `scope`：跨项目通用知识与用户偏好用 `user`；项目相关的用 `project`。

### 2.3 content 建议格式

```
<命题>：<结论>。条件：<适用条件>。来源：<L1-id>。
```

示例：

```
Vite 开发服务器默认端口：5173。条件：未在 vite.config 中显式指定 server.port。来源：kb-20261009-0001。 [src:kb-20261009-0001]
```

### 2.4 一次性保存建议（多字段）

- 一条 L1 原文卡通常产出 1 - 3 条 L2 条目（一条主结论 + 必要的前提/条件条目）。
- 同一次摄入的多条建议用 `engram_save` 的 `items` 批量写入，单条失败不影响其余。
- `kind` 只写英文：`fact` / `preference` / `decision` / `episode` / `skill`；**不要传 `room`**（房名由 engram 自动排桩，见 §2.1）。

---

## 3. status 五状态（与 `review-workflow.md` 一致）

```
inbox ──agent 提案──> proposed ──用户批准──> approved ──入库──> indexed
                        │                     ▲
                        ├──用户驳回──> rejected
                        └──用户要改──> needs_edit ──agent 改完──> proposed
```

| status | 含义 | 允许的动作 |
|---|---|---|
| `inbox` | 已进入系统（`_inbox/`），尚未生成提案 | agent 生成提案 |
| `proposed` | 提案已在 `_review/queue/`，等待用户批阅 | **禁止写 L2/L3**；只能读 |
| `approved` | 用户已批准，正在执行入库四动作 | 执行入库 |
| `indexed` | 入库完成：L1 已落盘、L2 已写、L3 已更新 | 后续修正走 supersedes |
| `rejected` | 用户驳回，归档 `_review/rejected/` | 可重新提案（新 id） |
| `needs_edit` | 用户要求修改，等 agent 改完重新提案 | agent 修改后回到 `proposed` |

---

## 4. L3 知识页 frontmatter

```yaml
---
category: 技术工程
updated_at: 2026-10-09T12:00:00+08:00
entry_count: 0
---
```

**纪律**：L3 是**消化层 + 综合层**（契约 §9）。几千份原文**不许**塞进知识页；原文只在 L1，L2 只放提炼后的条目，L3 只放该大类的**消化笔记（五要素：`## <主题>` → `### 核心结论` / `### 原理与推导` / `### 方法与步骤` / `### 适用条件与边界` / `### 易错点` / `### 相关条目（entry ids）`）**、总览与目录（每条一行索引 + `[src:<id>]` 链接，索引追加在文末）。

> 消化五要素的定义与质量自检见 `_system/learning.md`；一条 L2 条目只承载「单条命题结论」，推导/步骤/边界/易错点属于 L3。
