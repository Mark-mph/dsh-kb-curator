# 冲突仲裁算法 arbitration（冻结契约 v1 §5，逐条实现）

> **本文件是契约 §5 的逐条落地，不得增删规则。** 任何想要「优化」的念头都必须先回到 Lead 改契约。
> 执行者：agent（skill `kb-curator`）。每次回答涉及多来源的同一命题时，必须先跑本算法，再组织答案。
> **顺序（v1.1 定案）**：① 提取冲突 → ② 同领域过滤 → ③ 时效过滤 → ④ **正误推理（新增，先于来源等级的独立步骤）** → ⑤ 来源等级投票 → ⑥ 优先级 → ⑦ 置信度打破平局 → ⑧ 仍打平 → 标记「存在冲突」，不擅自裁定，送待审队列。另有第 ⑨ 条「库内 vs 联网」细则。
> 相关数值定义见 `priority.yml`（来源等级 / priority / confidence / 优先级缺省标注）。

## 输入 / 输出

```
输入：问题 q、候选条目集合 C（来自 L2 检索 + 可能的联网搜索）
输出：{ chosen_ids, outcome: resolved|conflict, conflict_ids, verdicts, 依据说明 }
      verdicts = [ { id, verdict: sound|erroneous|undecidable, reason, basis } ]   # 第 4 步产出
```

候选条目字段（来自 L1 frontmatter，L2 条目继承同一套）：`id, category, subcategory, proposition_key, source_type/来源等级, priority, confidence, valid_from, valid_until`。

---

## 第 1 步 提取冲突（含聚类）

```
groups = group_by(C, keys = (category, subcategory, proposition_key))
# proposition_key 形如 前端/构建工具/vite-默认端口；同一命题的多条说法靠它归到同一组
# 每个 group 内部才进行比较；跨组条目互不竞争
# 组内只有 1 条说法 → 无「冲突」可比，不做裁定（但 agent 在提案/回答时发现明显谬误，
#   仍应显式指出并标 verdict=erroneous 送审，只是不算仲裁步骤）
```

## 第 2 步 同领域过滤

```
C1 = [ item in C if 相关(item.category, q) or 相关(item.subcategory, q) ]
     # 相关 = 与 q 的领域一致、或 q 明确指向该 category/subcategory
C1 为空 → 直接返回 outcome="resolved", chosen_ids=[], 依据说明="库内无相关领域条目"
```

## 第 3 步 时效过滤

```
剔除：   item.valid_until 非空 且 item.valid_until < now        # 过期，不参与裁定
降级：   item.valid_from  非空 且 item.valid_from  > now        # 标记为「未来条目」
         → 不参与裁定，但必须在提示中列出（例：「另有 1 条将于 2026-12 生效的条目，未参与本次裁定」）
保留：   valid_until 为空 = 长期有效
```

## 第 4 步 正误推理（新增，独立于来源等级）

> 用户要求：「有些资料会有谬误，遇到资料信息矛盾时候自行推理正误，如果觉得都没问题再按优先级来」。
> 这一步**先于**来源等级：先把可判的谬误挑出来，剩下的才比来源/优先级/置信度。

对组内**每条**冲突声明做**可检验**检查（三项，逐项给依据）：

```
a. 内部自洽：推导 / 计算 / 量纲 / 逻辑是否自相矛盾
b. 与公认基准一致：教材、标准定义、学科共识
c. 与库内其他高置信条目相容
```

产出每条条目的 verdict：

```
verdict = erroneous    ：能明确判定为谬误（必须写出具体理由：推导 / 反例 / 量纲 / 定义冲突）
verdict = sound        ：通过 a/b/c 检查
verdict = undecidable  ：都自洽，或属**不同条件 / 版本 / 参数 / 模型假设**（不算错，只是范围不同）
```

处理：

```
- verdict=erroneous 的条目：
    · 不得进入 chosen_ids，也不得作为结论输出
    · **必须在回答里显式告知用户**（「我把 <id> 的说法判为谬误，理由是…」），绝不静默丢弃
    · 同时生成一条待审记录放入 _review/queue/（含原说法、来源 [src:<id>]、判定理由），
      让用户最终确认；用户可推翻
- 剩余条目（sound + undecidable）→ 继续第 5 步
- 整组都判不出来（全部 undecidable）→ 照常进第 5 步，不得硬判
```

硬约束（写死，不得违反）：

```
1. **禁止仅凭「更常见 / 更符合直觉 / 更权威的感觉」判错**——必须有可检验的理由（推导 / 反例 / 量纲 / 定义冲突）。
2. **判错是提案不是终审**：用户可推翻；agent 不得据此删除、改写任何库内资料或条目。
3. 判不出就写 undecidable，不许为了「给个结论」而强判 erroneous。
```

## 第 5 步 组内比来源等级 source_rank

```
For each group g:
  max_rank = max(item.source_rank for item in g)      # 只统计第 4 步后剩下的条目
  winners(g) = [ item in g if item.source_rank == max_rank ]
  # user_provided=100 > user_approved_web=60 > unapproved_web=20
  # 未审核的联网结果（unapproved_web）不参与裁定，见第 9 条
```

## 第 6 步 同等级比 priority

```
若 len(winners(g)) > 1:
  max_priority = max(item.priority for item in winners(g))     # 5 最高
  winners(g) = [ item in winners(g) if item.priority == max_priority ]
# ⚠️ 用户尚未规定优先级：当前 priority 由 agent 自行推理判断，提案中必须标注
#    by: agent、pending_user: true（详见 priority.yml）；用户一旦规定，以用户规定为准
```

## 第 7 步 仍相同比 confidence

```
若 len(winners(g)) > 1:
  max_conf = max(item.confidence for item in winners(g))       # 0-1
  winners(g) = [ item in winners(g) if item.confidence == max_conf ]
```

## 第 8 步 仍无法分出胜负 → conflict

```
若 len(winners(g)) > 1:
  outcome = "conflict"
  conflict_ids += winners(g) 涉及的全部条目 id
  对每条 action：
    - 不选边（绝不擅自挑一条当结论）
    - 把涉及条目标记 conflicted
    - 生成一条冲突提案放入 _review/queue/（含各方说法、各自来源 [src:<id>]、分歧点）
    - 回答中显式写出：「库内存在冲突说法，已列入待审队列，请你裁定」
若所有 group 都 len(winners(g)) == 1：
  chosen_ids += 该唯一胜出条目；outcome = "resolved"
```

## 第 9 条 库内 vs 联网冲突

```
若 库内条目 与 联网结果 就同一命题给出不同说法：
  - 先跑第 4 步正误推理：联网结果若明显可判谬误 → 标 erroneous，只在末尾提示，不入库、不参与裁定
  - 库内 user_provided 条目优先（chosen = 库内条目）
  - 未审核的 web 结果**不参与裁定**
  - 未审核 web 结果只能作为「补充视角」附在答案末尾，并明确标注「未审核，仅供参考」
  - 该补充视角不得写 L2 / L3，也不得进入 chosen_ids
```

---

## 答案纪律（契约 §5 末）

- 引用任何条目必须写出 `[src:<L1-id>]`，让用户能点回原文核对。
- 没有 `[src:<id>]` 的说法不得作为结论输出。
- 输出必须附「依据说明」：每个 chosen 条目写清它靠哪一步胜出（第 4 步判定 / 来源等级 / priority / confidence）。
- 第 4 步有任何 verdict 时必须写出来：「<id> 的说法我判为谬误 / 无法判定，理由是…（已列入待审队列）」，不得只字不提。
- `outcome=conflict` 时，答案不得给出单一结论，只能陈述分歧 + 送审提示。
- 结论定了以后，按 `learning.md` 的消化五要素组织答案（核心结论 / 原理与推导 / 方法与步骤 / 适用条件与边界 / 易错点），让用户拿到的不是一条干巴巴的结论。

## 与审核工作流的关系（不属于仲裁规则，仅说明衔接）

- 仲裁产出的冲突提案、以及第 4 步的「谬误待审记录」= 普通 `proposed` 提案，走 `review-workflow.md` 的五状态流程。
- 用户裁定后，agent 才可写 L1 / L2 / L3；`proposed` 状态下严禁写 L2 与 L3。
- 消化产物（知识页 `## <主题>` 内容、L2 条目正文）同样必须先提案、后批准，见 `learning.md`。
