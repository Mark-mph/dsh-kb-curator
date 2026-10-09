# 审核工作流 review-workflow（冻结契约 v1 §6）

> **安全阀：`proposed` 状态下 agent 不得写 L2（engram）与 L3（知识页）；任何绕过均为违规。**
> 对应字段定义见 `entry-schema.md`；提案模板见 `_templates/review-proposal.md`。

## 1. 五状态 + 两终态

```
inbox ──agent 提案──> proposed ──用户批准──> approved ──入库──> indexed
                        │                     ▲
                        ├──用户驳回──> rejected
                        └──用户要改──> needs_edit ──agent 改完──> proposed
```

| 状态 | 落在哪 | 谁推动 | 下一步 |
|---|---|---|---|
| `inbox` | `_inbox/`（原文副本，用户原文件不动） | 用户喂料 / `kb.ps1 add` | agent 分类、生成提案 |
| `proposed` | `_review/queue/<id>.md` | agent | **等用户批阅**（不得写 L2/L3） |
| `approved` | `_review/approved/<id>.md` | 用户说「批准」 | 执行批准后四动作 |
| `indexed` | L1 + L2 + L3 均已写入 | agent | 归档完成 |
| `rejected` | `_review/rejected/<id>.md` | 用户说「驳回」 | 归档理由；可带修改后重新提案 |
| `needs_edit` | 提案仍在队列，标 `needs_edit` | 用户说「要改」 | agent 改完 → 回到 `proposed` |

## 2. 每个 proposed 提案必须包含（缺一不可，共 6 项）

> **计数口径（与技能侧统一）**：「建议优先级」与「置信度」**分开计**，所以是 **6 项**，不要合并成 5 项。

1. 原文摘要
2. 建议分类（大类 / 子类 + 依据）
3. 建议优先级 `priority`（1-5）
4. 置信度 `confidence`（0-1）
5. **将要写入 engram 的条目正文**（含 `[src:<id>]`）
6. 将要更新的知识页 diff（`pages/<大类>.md` 的哪一节加哪一行）

## 3. 用户批准后的四动作（依次执行，每一步都写 `_system/log.jsonl`）

| 序 | 动作 | 落点 | kb.ps1 |
|---|---|---|---|
| ① | L1 落盘 | `library/<大类>/<子类>/<yyyy-mm-dd>-<slug>.md` | `approve` 自动完成 |
| ② | `engram_save` 写 L2 | engram SQLite（`~/.dsh/engram/user.db`） | `approve` 输出待执行的条目正文，由 agent 调 `engram_save` |
| ③ | 更新知识页 | `pages/<大类>.md` 追加综述与索引行 | **agent 在批准后自行更新**（`kb.ps1` 默认不动本页，仅 `approve <id> -UpdatePage` 才机械追加一行；**没有** `-NoPageUpdate` 参数） |
| ④ | 提案归档 | `_review/approved/<id>.md` | `approve` 自动完成 |

② 完成后把该条 `status` 推进到 `indexed`（L2 未写的条目不得称 indexed）。

## 4. 用户驳回

- 提案追加「驳回记录（时间 + 理由）」后移入 `_review/rejected/`；
- L1 材料从 `_inbox/` 移入 `_inbox/_rejected/`（**用户原始文件始终不动**）；
- 写日志 `reject`。

## 5. 用户要改（needs_edit）

- 提案留在 `_review/queue/`，追加「待修改点」；agent 修改后重新生成提案内容；
- 修改前后都必须保持 `proposed` 状态语义：**修改期间依然不得写 L2/L3**。

## 6. 无例外清单

- agent **绝不能**在用户批准前写入 L1（`library/`）、L2（engram）、L3（`pages/`）。
- `_inbox/`、`_review/` 属于过程区，可以写；`library/`、`pages/`、engram 属于成果区，必须批准后才写。
- 未审核的联网结果永远不参与裁定，也不得写入成果区。
- 用户口头/文字说的「批准」= 批准**指定 id** 的那一条提案；没有指定 id 时必须先问清是哪一条。
- 任何情况下不得删除用户已有资料（只许移动与追加）。
