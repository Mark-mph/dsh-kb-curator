# 三层架构（L1 / L2 / L3）

> 依据：`references/contract.md` §1、§2、§3。契约是唯一事实来源。

## 1. 三层各是什么

| 层 | 定位 | 存放位置 | 写入时机 | 粒度 |
|---|---|---|---|---|
| **L1 原始库** | 原文，人眼可读、可 git 管理 | `<KB>/library/<大类>/<子类>/<yyyy-mm-dd>-<slug>.md` | 用户批准后 | 原文逐字，不改写、不摘要、不删减 |
| **L2 检索层** | 记忆条目，供 engram 混合检索 | engram 插件的本地 SQLite 库（具体位置由 engram 插件决定） | 用户批准后 `engram_save` | 一句话命题 + 条件 + 来源 |
| **L3 知识页** | 每个大类一张**消化页** | `<KB>/pages/<大类>.md` | 用户批准后更新 | 五要素消化块（概念/原理/步骤/边界/易错点）+ 索引，不是原文堆放处 |

**换检索服务的可移植性**：原文永远在 L1 本地文件里。换掉 engram、换掉搜索工具，L1 一字不动，最多重建 L2/L3。这是契约 §0 约束 4。

## 2. 为什么必须分三层（别混层）

- 把原文塞进 L2 → engram 变成文件堆，检索全是长文本，召回质量崩，且**用户批准粒度失焦**（批准的是"一句话结论"还是"一整篇"，说不清）。
- 把原文塞进 L3 → 知识页退化成复制粘贴仓库，失去"消化层"的意义；契约 §1 明文禁止。
- 只保留 L2 不留 L1 → 用户无法核对原文，`[src:<L1-id>]` 断链，辨别能力无从谈起。

## 3. 目录布局（契约 §2，kb-architect 用 `kb.ps1 init` 创建）

```
<KB>\                             # 知识库根目录 = kb.cmd / kb.ps1 所在目录（引擎自定位）；用户要求所有资料集中在这一处
  kb.cmd                          # 入口包装器：powershell.exe -NoProfile -ExecutionPolicy Bypass -File kb.ps1 %*
  kb.ps1                          # 真正的实现（UTF-8 with BOM）
  kb.config.json                  # root / 默认分类 / storage 磁盘阈值 / 版本
  README.md                       # 中文用户手册
  _inbox/                        # L0：用户扔进来的原始资料，未处理
    _rejected/                   # 被驳回的原文归档（不删除）
  _review/
    queue/                       # 待审提案（一 proposal 一个 .md，含 diff 预览）
    approved/                    # 批准后提案存档（审核痕迹）
    rejected/                    # 驳回提案存档（含驳回理由）
  _system/
    taxonomy.yml                 # 大类 → 子类 → 触发关键词
    priority.yml                 # 来源等级 + 优先级 + 置信度规则
    arbitration.md               # 冲突仲裁算法（逐条对应契约 §5）
    learning.md                  # 消化学习层（五要素、知识页结构、硬边界）
    entry-schema.md              # L1 frontmatter + L2 条目字段规范
    review-workflow.md           # 五状态审核工作流
    log.jsonl                    # 追加式操作日志
  _templates/
    source-note.md               # L1 原文卡模板
    memory-entry.md              # L2 记忆条目模板
    knowledge-page.md            # L3 知识页模板
    review-proposal.md           # 待审提案模板
  _staging/                      # 临时中间件（可清理，主要在 ocr/ 下）
    ocr/{pages,chapters,probe-out}
  _sources/                      # 用户原始文件副本（PDF 等大文件；未经用户同意不要删）
  library/<大类>/<子类>/<yyyy-mm-dd>-<slug>.md
  pages/<大类>.md
```

**目录纪律**：不手搓目录树（`kb.ps1 init` 负责）；不删除已有资料（只移动 / 追加）。

**磁盘纪律（用户硬要求：知识库所在盘快存满必须提前告知）**：
- 收料 / 批量写入 / 导入大文件**之前**先跑 `& "<KB>\kb.cmd" status`（只读，不写日志）。
- 剩余 < `storage.warn_free_gb`（当前 20 GB）或输出 `[磁盘告警]` → **必须在回复里明确告诉用户**，并给可清理项
  （`_staging\` 临时中间件、`_inbox\_rejected\`、已驳回提案；`_sources\` 是用户原始文件，**未经同意不要删**）。
- 剩余 < `storage.block_free_gb`（当前 5 GB）→ `add` 拒绝收料（exit=1）；**停止收料**并告知用户、等指示。
- 阈值只在 `<KB>\kb.config.json` 的 `storage` 里，**不写死在技能/脚本**，改配置即可调整。
- **所有资料只能落在这一个文件夹内**（用户原话：不要存得到处都是）——不要另建副本、不要散落到 `%TEMP%` 或 workspace。

## 4. L1 原文卡 frontmatter（字段名固定，契约 §3）

```yaml
id: kb-20261009-0001              # 固定格式 kb-<yyyymmdd>-<4位序号>
title: "标题"
category: 技术工程                 # 必须是 taxonomy.yml 里的大类
subcategory: 前端                  # 可为空
source_type: user_file | user_text | web
source_url: ""                    # web 必填
fetched_at: ""                    # web 必填，ISO8601
added_at: 2026-10-09T12:00:00+08:00
content_hash: "<sha256 原文>"      # 去重与版本比对
status: inbox | proposed | approved | rejected | needs_edit | indexed
priority: 3                       # 1-5，5 最高，用户可调
confidence: 0.8                   # 0-1，agent 提案、用户可改
valid_from: ""                    # 时效起点，可空
valid_until: ""                   # 时效终点，空=长期有效
supersedes: []                    # 被本条取代的旧条目 id
tags: []
proposition_key: ""               # 命题键，仲裁按它聚类
```

字段使用要点：
- `id` 生成前先看当日已有 id（L1 目录 + `_review/queue/` + `_review/approved/`），取最大序号 +1，避免重号。
- `content_hash` = sha256(原文全文)。**喂料第一步就算，先查重再落盘**。
- `proposition_key` 形如 `前端/构建工具/vite-默认端口`；同一命题的不同说法共用同一个 key，仲裁第 3 步就靠它聚类。
- `valid_until` 空 = 长期有效；版本号 / 价格 / 政策 / 人事类内容必须填或显式标注时效敏感。
- `supersedes` 填被本条取代的旧条目 id；取代关系与 engram 的 `engram_update` 归并同时做。

## 5. L2 条目写法（写入 engram，契约 §4）

固定格式：

```
<命题>：<结论>。条件：<适用条件>。来源：<L1-id>。
```

示例：

- `Vite 默认端口：5173。条件：vite >= 2 且未在 vite.config 里改 server.port。来源：kb-20261009-0001。`
- `用户偏好：包管理用 pnpm 而非 npm。条件：所有前端项目。来源：kb-20261009-0002。`

强制项：
1. 每条 content 必须带来源（`[src:<L1-id>]` 或 `来源：kb-…`），否则不合格。
2. `kind` 按房间路由：`fact` / `preference` / `decision` / `episode` / `skill`。
3. `scope`：跨项目通用与偏好 → `user`；项目相关 → `project`。
4. 高度相似已有条目 → `engram_update` 归并，不许造重复。

## 6. L3 知识页写法（消化层）

**每份批准的资料都要被消化成一个主题小节**，结构固定（五要素的落点，见 `learning.md`；
原文未涉及的要素要写明"原文未涉及"，不许跳过）：

```markdown
## <主题>
### 核心结论
### 原理与推导
### 方法与步骤
### 适用条件与边界
### 易错点
### 相关条目（entry ids）
```

**该写**：
- 页面顶部：一句话定位（这个大类覆盖什么、不覆盖什么）+ 未决事项（冲突待裁定、即将过期的条目）。
- 每个主题小节：上面那六段；结论要能**直接用来回答问题**——为什么成立、怎么做、什么时候不适用。
- 页面末尾：`## 已入库条目索引`（格式不变，追加一行 `[src:<L1-id>]` + 一行摘要）+ 维护信息（最后更新日期、条目数）。
- 跨多条 L1 得到的规律 / 判断（每条附来源）。

**不该写（反例）**：

```markdown
<!-- 反例：把原文搬进 L3 -->
## Vite 配置
Vite 是一个基于 ESM 的前端构建工具，由 Vue 作者尤雨溪开发。它利用浏览器原生
ESM 支持……（此处粘贴了 2000 字原文）
```

正确写法：

```markdown
## 构建工具
- Vite 默认端口 5173；改端口改 `server.port`。[src:kb-20261009-0001]
- 本项目统一用 pnpm，不用 npm（用户偏好）。[src:kb-20261009-0002]
```

**长度控制**：单张知识页建议 ≤200 行。超了就说明细节该下沉回 L1/L2，L3 只留索引与结论。

## 7. 层间一致性检查（每次批准入库后跑）

- [ ] L1 有该 id 的文件，frontmatter `status: approved`（**由 `kb.cmd approve` 落定，不是 `indexed`**；`indexed` 只属于 `_review/approved/<id>.md` 归档提案）。
- [ ] L2 有对应条目，content 内的来源 id 与 L1 id 完全一致（逐字符比对）。
- [ ] L3 该大类页面出现该 id 的 `[src:...]` 链接。
- [ ] `_review/approved/` 有提案存档，`_review/queue/` 里已无该提案。
- [ ] `_system/log.jsonl` 追加了本次动作那一行。

五处齐了才算 `indexed`；缺一处不要声称"已入库"。
