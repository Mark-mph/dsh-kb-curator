# 智能知识储备体系（Knowledge Base）

> 一个**本地优先、免费优先、用户审核后才入库**的个人知识库。
> 资料进来先躺 `_inbox/`；agent 读完写提案；**只有你本人点批准**，才会落进 L1 原文库、写进 L2 记忆、更新 L3 知识页。
>
> **知识库根目录：本文件所在的那个文件夹。** 引擎是**自定位**的（`kb.ps1` 用 `$PSScriptRoot`），你把 `engine/` 复制到哪里，哪里就是知识库根目录；所有资料集中在这一个文件夹里，不要散落到别处。
> `kb.config.json` 的 `root` 只是给人看的说明字段，程序不读取它；真正的权威是脚本自身所在目录。本文出现的相对路径都相对知识库根目录解析。
> 另一条硬性约束：**知识库所在磁盘快存满必须提前告知用户** —— 见 §8「磁盘空间策略」。

---

## 1. 三层结构

| 层 | 是什么 | 位置 | 谁写 |
|----|--------|------|------|
| **L1 原文库** | 资料原文 + 固定 frontmatter（可溯源、可引用） | `library/<大类>/<子类>/<yyyy-mm-dd>-<slug>.md` | 仅 `kb.ps1 approve` 落盘 |
| **L2 记忆** | 可检索的命题（事实/偏好/决策/经历/技法） | engram SQLite（`~/.dsh/engram/`） | 仅 agent 在**用户批准后**调用 `engram_save` |
| **L3 知识页** | 每大类一张**消化页**（`## <主题>` 下写核心结论 / 原理推导 / 方法步骤 / 适用边界 / 易错点）+ 索引 + 待裁定冲突 | `pages/<大类>.md` | agent 在批准后更新；**不放原文** |

设计原则：**原文留在 L1（不花钱、不丢），L2 只存提炼后的命题，L3 放消化后的理解（五要素）与目录。**
几千份原文永远不进知识页，否则页面会爆炸。

### 回答问题时

1. 先查 L2（engram 语义检索）拿到候选命题；
2. 按 `_system/arbitration.md` 的**仲裁顺序**裁定冲突：① 提取冲突 → ② 同领域过滤 → ③ 时效过滤 → **④ 正误推理（先判资料对错）** → ⑤ 来源等级 → ⑥ 优先级 → ⑦ 置信度 → ⑧ 仍打平就送审；
3. 引用必带 `[src:<L1-id>]`，可回 L1 查原文；
4. 用 L3 知识页里对应主题的**消化五要素**组织答案（结论 / 推导 / 步骤 / 边界 / 易错点），见 §7「学习层」；
5. 库里没有且允许联网时 → 联网结果标为**未审核（rank 20）**，只作「补充视角」，并提示你决定是否入库。

---

## 2. 目录地图

```
<知识库根目录>\            ← 你把 engine/ 复制到的地方
├─ kb.config.json          全局配置（root / 大类清单 / 默认值 / 付费开关 / 磁盘阈值）
├─ README.md               本文件
├─ kb.cmd                  **推荐入口**：包装 kb.ps1，固定带 -ExecutionPolicy Bypass（见 §3 说明）
├─ kb.ps1                  唯一工具：status / init / add / list-queue / show / approve / reject / search / page / log
├─ _inbox/                 收料区：刚喂进来的资料（未审核，绝不当作知识）
│   ├─ <id>-<slug>.md      原文副本（你的原文件不会被改动）
│   ├─ <id>-<slug>.meta.md 初始元数据：kb.ps1 add 给的分类/优先级建议，供 agent 写提案
│   └─ _rejected/          被驳回资料的去处
├─ _review/
│   ├─ queue/              待审提案 <id>.md（status: proposed）
│   ├─ approved/           已批准的提案（保留审核痕迹）
│   └─ rejected/           已驳回的提案（含驳回理由）
├─ _system/
│   ├─ taxonomy.yml        8 大类 → 子类 + 触发关键词（自动分类依据）
│   ├─ priority.yml        来源等级 100/60/20、priority 1-5、confidence 0-1、决胜顺序
│   ├─ arbitration.md      冲突裁定算法（9 步：①②③过滤 + **④正误推理** + ⑤⑥⑦比等级 + ⑧打平送审 + ⑨库内 vs 联网）
│   ├─ entry-schema.md     L1 frontmatter 全字段 + L2/L3 格式规范
│   ├─ review-workflow.md  五状态流转、提案必备项、批准后动作、安全阀
│   ├─ learning.md         消化学习层：消化产物五要素 + 知识页结构（怎么「会运用」）
│   └─ log.jsonl           操作日志（每行一个 JSON，只追加）
├─ _templates/             source-note / memory-entry / knowledge-page / review-proposal
├─ _sources/               **你的原始文件副本**（二进制，不加工；溯源与重跑 OCR 用，见下方说明）
├─ _staging/               OCR / 格式转换的**中间产物，可重建**（不当作知识，可清理）
│   └─ ocr/                pages（逐页文本）· chapters（分章 Markdown）· probe-out
├─ library/                已批准原文（L1），按 大类/子类 分层
└─ pages/                  知识页（L3），8 大类各一张
```

> `library/<大类>/` 下**不预建子类目录**：子类目录在 `approve` 落盘时**按需创建**（例如第一条「技术工程/通用」的资料被批准后，才会出现 `library\技术工程\通用\`）。
> `init` 只创建 8 个初始大类目录——这是设计如此，**不是漏建**。

> `_sources/`（**你的原始文件副本**，不加工、只存放，随资料增长会占空间）：**出厂为空**，你投进来的每一份原件都会在这里留一份只读副本。
> `_staging/ocr/`（**OCR / 格式转换中间产物，可随时重建**）：按需生成，典型结构 `pages/`（逐页文本）、`chapters/`（分章 Markdown）、`probe-out/`（探测产物）。**清理它不丢知识**，需要时可重跑 OCR 生成。

初始 8 大类：`技术工程`、`产品业务`、`学术研究`、`生活健康`、`财务投资`、`人文社科`、`工具流程`、`未分类`（兜底）。
要加新大类：改 `kb.config.json` 的 `categories`，并在 `_system/taxonomy.yml` 里补 `- name:` / `subcategories` / `keywords`，然后 `kb.cmd init`。

---

## 3. 五分钟上手

```powershell
$KB = "<知识库根目录>"           # 你把 engine/ 复制到的地方

& "$KB\kb.cmd" status                                # ⓪ 先看现状与盘剩余空间（只读，不写日志）
& "$KB\kb.cmd" init                                  # ① 建骨架（幂等，可反复跑）

# ② 喂一份资料（你的原文件不会被改动，只做副本）
& "$KB\kb.cmd" add -Path "D:\notes\vite-port.md"

# ③ 让 agent 读 _inbox/ 里的副本，按 _templates/review-proposal.md 写提案到 _review/queue/
& "$KB\kb.cmd" list-queue                            # ④ 看有哪些待审

# ⑤ 看详情，决定批准或驳回
& "$KB\kb.cmd" show kb-20261009-0001
& "$KB\kb.cmd" approve kb-20261009-0001
#   或
& "$KB\kb.cmd" reject kb-20261009-0001 -Reason "数字对不上"

# ⑥ 找东西 / 看知识页 / 看日志
& "$KB\kb.cmd" search "vite 端口"
& "$KB\kb.cmd" page 技术工程
& "$KB\kb.cmd" log -Tail 20
```

> **为什么统一用 `kb.cmd`，不直接跑 `kb.ps1`？**
> 当前会话的文件沙箱会给 `.ps1` 加一条 ACL，PowerShell 的授权管理器因此把它判定为不受信任，直接运行会报：
> `AuthorizationManager check failed.`（`PSSecurityException`）。
> 知识库换到任意根目录**都是如此**——实测
> `powershell -NoProfile -File "<知识库根目录>\kb.ps1" status` → `AuthorizationManager check failed.`（exit 1）。
> `kb.cmd` 内部固定执行 `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0kb.ps1" %*`，
> 加了 `-ExecutionPolicy Bypass` 即通过，所以调用方不必再关心执行策略。等价的手写形式是：
> `powershell -NoProfile -ExecutionPolicy Bypass -File "<KB>\kb.ps1" <命令>`。

> 本机没有 `pwsh`（PowerShell 7），系统自带的是 `powershell.exe` 5.1，脚本已兼容 5.1。
> `kb.ps1` 必须是 **UTF-8 with BOM** 保存，否则 5.1 会把中文读成乱码。
> `kb.cmd` 必须保持**纯 ASCII**：cmd.exe 用 OEM 代码页读 `.cmd`，中文注释会被当成命令执行并报一堆错。

---

## 4. 命令参考

| 命令 | 作用 | 关键说明 |
|------|------|----------|
| `status` | **看一眼现状**：固定根目录、磁盘剩余空间与两条阈值线、待审/已批准/已驳回提案数、L0 暂存 / L1 原文 / L3 知识页计数、日志行数、规范文件是否齐备 | **只读**：不写日志、不改任何文件；收料前应先跑（见 §8） |
| `init` | 建/补齐目录树与 8 张知识页骨架 | 幂等；只新建缺失项，绝不覆盖；同时打印磁盘剩余空间 |
| `add -Path <文件> [-Category <c>] [-Subcategory <s>] [-Title <t>] [-SourceType <t>] [-Url <u>] [-Priority 1-5] [-Confidence 0-1] [-Tags a,b] [-PropositionKey <k>] [-Force]` | 资料收进 `_inbox/` + 生成初始元数据 | **不生成提案**；命中相同 `content_hash` 会拒绝（`-Force` 强制再收一份） |
| `list-queue` | 列出 `_review/queue/` 待审提案 | 缺 `category`/`inbox_path` 的提案会给出警告 |
| `show <id>` | 查看提案 / 已归档提案 / L1 原文卡 | |
| `approve <id> [-UpdatePage]` | 用户批准：L1 落盘 + 提案归档 + 写日志 + **打印 agent 待办** | 默认不动 `pages/`；`-UpdatePage` 才机械追加一行索引 |
| `reject <id> -Reason "..."` | 用户驳回：提案归档 + 材料移入 `_inbox/_rejected/` | `-Reason` 必填（存档备查） |
| `search <query>` | 在 L1 原文库 / L3 知识页 / 待审队列里做**字面**检索 | 只是定位原文；答题请走 L2 + 仲裁 |
| `page [<大类>] [-Create]` | 查看知识页；不带参数列出全部 | |
| `log [-Tail N]` | 查看操作日志（默认 20 条） | |
| `help` | 帮助（默认命令） | |

**没有 `remove`/`del` 命令**——这个知识库只新增、只移动，永不删除你的资料。

---

## 5. 审核流程（五状态）

```
inbox ──agent 写提案──▶ proposed ──你批准──▶ approved ──入库──▶ indexed
                          │
                          ├──你驳回────────▶ rejected
                          └──你要改────────▶ needs_edit ──agent 改完──▶ proposed
```

- **提案**（`_review/queue/<id>.md`）必须写清：原文摘要、建议分类、建议优先级、置信度、**将写入 engram 的条目正文**、将更新的知识页 diff。
- **安全阀**：只要还是 `proposed`，就**不许**写 L1（`library/`）、不许写 L2（engram）、不许改 L3（`pages/`）。
- **批准后**四件事：
  1. L1 原文落盘 `library/<大类>/<子类>/`（`kb.ps1 approve` 做）；
  2. 提案移入 `_review/approved/`（`kb.ps1 approve` 做）；
  3. 写 `_system/log.jsonl`（`kb.ps1 approve` 做，`l2_pending: true`）；
  4. agent 接着做：`engram_save`（`content` 必须含 `[src:<id>]`）+ 更新 `pages/<大类>.md`；完成后把归档提案 `status` 改成 `indexed`，并补一行 `{"action":"l2-saved", ..., "l2_pending":false}`。

> **`kb.ps1` 永不写 engram**：engram 是带关系边和本地嵌入的 SQLite 记忆图，用 PowerShell 绕过插件直接改库会破坏图一致性。

---

## 6. 冲突怎么办（仲裁摘要）

完整算法见 `_system/arbitration.md`（契约 §5 逐条落地，不得增删）。摘要：

1. **提取冲突**：按 `(category, subcategory, proposition_key)` 聚类 → 2. 同领域过滤 → 3. 时效过滤（过期剔除；未来条目降级提示）→ 4. **正误推理（新增，先于来源等级）**：对每条说法做可检验检查（内部自洽 / 与教材·标准·共识一致 / 与库内高置信条目相容）；能明确判为谬误的 → `verdict=erroneous` + 具体理由（推导 / 反例 / 量纲 / 定义冲突），**显式告诉你**并生成待审记录请你确认，**绝不静默丢弃**；判不出（都自洽，或只是条件/版本/参数不同）→ 继续下一步 → 5. 比来源等级 **100（你提供）> 60（你审核过的联网）> 20（未审核联网）** → 6. 比 `priority`（1-5；**你尚未规定优先级，当前由 agent 自行推理判断并标注 `by: agent` / `pending_user: true`**）→ 7. 比 `confidence`（0-1）→ 8. 仍然平手：**不选边**，标记冲突、生成冲突提案进待审队列，并在回答里明确写「库内存在冲突说法，已列入待审队列，请你裁定」→ 9. 库内 vs 联网：库内你提供的优先；**未审核的联网内容不参与裁定**，只在末尾作「补充视角」并标注未审核。

**硬约束**：**禁止仅凭「更常见 / 更符合直觉 / 更权威的感觉」判错**——必须有可检验的理由；**判错是提案不是终审，你随时可以推翻**。

回答纪律：任何结论都要带 `[src:<L1-id>]`，可回溯；有正误判定时必须把判定与理由一并写出来。

---

## 7. 学习层（消化理解，不只存储）

> 你的要求：「不仅做到存储和筛选，还能通过自行学习，消化理解会运用这些信息资料，为以后我咨询你相关问题打基础」。

入库不只是「存起来」，agent 还要把资料**消化**成能直接用的理解，写进 L3 知识页的 `## <主题>` 里。完整定义见 `_system/learning.md`。

**消化产物五要素**（缺一不可，缺的要显式写「待补」）：

| # | 要素 | 回答「什么」 |
|---|------|--------------|
| ① | 概念与定义 | 术语 / 符号 / 单位是什么，怎么读 |
| ② | 原理与推导链 | 为什么成立、前提假设是什么（推导可检验） |
| ③ | 方法与步骤 | 遇到这类问题怎么做，可执行流程 + 小例子 |
| ④ | 适用条件与边界 | 什么时候能用、什么时候失效 |
| ⑤ | 易错点与联系 | 常见误区错在哪 + 前置 / 后继 / 易混对比 |

**它在问答时的作用**：提问时先用 L2 检索 + `arbitration.md` 仲裁定出该采信哪条（含「正误推理」结论），再用知识页对应主题的五要素组织答案——你会拿到**结论 + 推导 + 步骤 + 边界 + 易错点**，而不是一条干巴巴的断言；每条仍带 `[src:<id>]` 可点回原文。

**两条边界**：

- **`kb.ps1` 不会引入任何 LLM 依赖**（保零成本、可离线跑）：消化由 agent 完成，脚本只做收料/落盘/归档/日志。
- **消化产物仍必须你先批准**：写进 `pages/`（L3）和 engram（L2）之前一律停在待审队列，`proposed` 状态下不许落库（和其他资料同一条安全阀）。

---

## 8. 磁盘空间策略（所在盘快存满要提前告诉你）

> 硬性约束：**知识库集中在同一个文件夹里；该磁盘快存满必须提前告知用户**。

| 线 | 配置项（`kb.config.json` → `storage`） | 默认 | 触发时的行为 |
|----|----------------------------------------|------|--------------|
| **提醒线** | `warn_free_gb` | 20 GB | `add` 打印 `[磁盘告警]`，**仍然放行**本次收料；**agent 必须立刻转告你**并给出清理/迁移建议 |
| **拒绝线** | `block_free_gb` | 5 GB | `add` 打印 `[错误] … 已拒绝本次收料`，**exit 1**，不落 `_inbox/`；agent 不得绕过（不许用 `-Force` 或手动复制硬塞），必须先与你商量腾空间 |

- **检查点**：每次收料（`add`）之前自动检查；`init` 也会打印当前剩余空间；`kb.cmd status` 可随时只读查询。
- **agent 的义务**：任何收料、或在知识库下的大批量写入（OCR 产物、批量落盘 L1）之前，**先跑 `kb.cmd status`**；只要出现 `[磁盘告警]`，必须在答复里显式告诉你（不许默默继续）。
- **改阈值**：直接编辑 `kb.config.json` 的 `storage.warn_free_gb` / `storage.block_free_gb`（数字，单位 GB），改完立即生效，无需重跑 `init`。
- **省空间优先级**：`_staging/`（OCR 中间产物，可重建）→ `_sources/` 里已消化完的历史原件 → `library/` 原文（最后才动，且脚本**永不自动删除**任何资料）。
- 现状：`kb.cmd status` 显示所在磁盘剩余 **373.1 GB**（预警线 20 GB / 拒绝线 5 GB）——离两条线都很远。

---

## 9. 成本与隐私

- 默认配置 **`paid_services_allowed: false`**，`kb.config.json` 的 `forbidden_services` 列了禁止项（Hindsight 云、付费嵌入 API 等）。
- 只有你主动调用的云端大模型会花钱，其余全本地、免费。
- 所有原文只存在本地磁盘（L1）和你自己的 engram 库里，不上传第三方。

`kb.config.json` 关键项：

| 键 | 默认 | 含义 |
|----|------|------|
| `default_category` / `default_subcategory` | `未分类` / `通用` | 分类拿不准时的落点 |
| `l2_scope_default` | `user` | 通用知识/偏好写 user 库；项目知识写 project 库 |
| `require_approval_before_l2_l3` | `true` | 安全阀开关，**不建议关** |
| `paid_services_allowed` | `false` | 是否允许付费服务 |
| `forbidden_services` | 列表 | 明令禁止的付费/云端服务 |
| `root` | `"."` | 说明性字段，程序不读取；真正的根目录是 `kb.ps1` 所在目录 |
| `storage.warn_free_gb` / `storage.block_free_gb` | `20` / `5` | 磁盘**提醒线 / 拒绝线**（GB），见 §8「磁盘空间策略」 |

---

## 10. 出问题了

| 现象 | 处理 |
|------|------|
| `AuthorizationManager check failed` | 你直接调了 `kb.ps1`（沙箱给 `.ps1` 加了 ACL，授权管理器拒绝），改调 `kb.cmd` |
| `kb.cmd` 吐出一堆 `'xxx' is not recognized as an internal or external command` | `kb.cmd` 里被写入了非 ASCII 注释；cmd.exe 用 OEM 代码页读它。保持该文件**纯 ASCII** |
| 中文乱码 | `kb.ps1` 不是 UTF-8 with BOM；重新以「UTF-8 带 BOM」保存 |
| `list-queue` 是空的 | `add` 只收料不生成提案，这是设计使然；提案要 agent 读完资料后写 |
| `approve` 报缺 `inbox_path` | 提案缺字段。按 `_templates/review-proposal.md` 补 `inbox_path`（指向 `_inbox/` 里的副本） |
| 找不到 id | `list-queue` 看待审；已归档的去 `_review/approved/`、`_review/rejected/` 找 |
| 想找回被驳回的资料 | `_review/rejected/<id>.md`（理由）+ `_inbox/_rejected/`（原文副本） |
| `init` 报缺规范文件 | 按提示从备份恢复；`init` 只建目录和知识页骨架，不重建规范文件 |
| 看到 `[磁盘告警]` | 知识库所在盘剩余空间已低于提醒线 `storage.warn_free_gb`（默认 20 GB）。按 §8 的顺序清理（先 `_staging/`）；agent 会同时把告警转告你 |
| `add` 报「已拒绝本次收料」 | 剩余空间低于拒绝线 `storage.block_free_gb`（默认 5 GB），本次收料被挡下且 **exit 1**。先腾空间，不要绕过 |
