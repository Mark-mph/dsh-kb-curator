# 冲突仲裁（八步，冻结算法）

> 依据：`references/contract.md` §5 + 用户要求 A「有些资料会有谬误，请你在以后遇到资料信息矛盾时候自行推理正误，
> 如果你觉得都没问题就按我喂完资料后规定的优先级来，现阶段我还没有规定优先级，请自行推理判断」。
> 契约 v1.1 §5 定案顺序（内含第 ⑨ 条「库内 vs 联网」细则）；**逐条实现，不许增删步骤、不许自创规则。**
> 系统侧 `_system/arbitration.md`（kb-architect 维护）是同一份定案的落地版；两者**必须一致**。
> 若发现两侧不一致（例如对方缺第 ④ 步正误推理）→ **回报 Lead**，**绝不允许两边各写一套**。

## 1. 输入 / 输出

```
输入：问题 q、候选条目集合 C（来自 L2 检索 + 可能的联网搜索）
输出：{ chosen_ids, outcome: resolved|conflict, conflict_ids, verdicts, 依据说明 }
      verdicts = [ { id, verdict: sound|erroneous|undecidable, reason, basis } ]   # 第 ④ 步产出
```

`verdict=erroneous` 的条目**必须同时出现在「给用户的显式告知」与「待审队列」两处**，不得静默丢弃（契约 §5）。

第 ④ 步的正误判定**逐条记录为 `verdict`**，写进「依据说明」，取值只有三个：

| verdict | 含义 | 后续动作 |
|---|---|---|
| `sound` | 该说法自洽且不与公认基准冲突 | 留在候选池，进入第 ⑤ 步 |
| `erroneous` | 能**明确判定为谬误** | 移出候选池 + **显式告知用户**（绝不静默丢弃）+ 生成待审记录交用户最终确认 |
| `undecidable` | 无法判定（都自洽，或属不同条件/版本/参数/模型假设） | 留在候选池，进入第 ⑤ 步 |

## 2. 八步算法（照做）

```
# 1) 提取冲突
#    按 (category, subcategory, proposition_key) 聚类；同一 group 内出现不同结论 = 存在冲突
#    proposition_key 形如 前端/构建工具/vite-默认端口；只有同 group 的条目才互相竞争
#    若没有任何 group 出现不同结论 → 无冲突，直接按正常召回回答（不必跑下面步骤）

# 2) 同领域过滤
C1 = [e for e in C if 与 q 相关(e.category, e.subcategory, q)]
#    判定：category/subcategory 命中 q 的主题，或条目 proposition_key 前缀命中
#    C1 为空 → outcome="resolved", chosen_ids=[], 依据说明="库内无相关领域条目"

# 3) 时效过滤
now = 当前时间
C2   = [e for e in C1 if not (e.valid_until and e.valid_until < now)]   # 过期剔除
future = [e for e in C1 if e.valid_from and e.valid_from > now]          # 未来条目：不参与裁定，但要提示

# 4) 正误推理（新增，本算法最重要的一步；细则见 §3）
for e in C2:
    e.verdict = 可检验检查(e)          # sound | erroneous | undecidable
    若 erroneous:
        移出候选池
        在回答里显式告知用户：哪条、为什么错、凭什么（推导/反例/量纲/定义冲突）
        生成待审记录 → _review/queue/（status=proposed，由用户最终确认）
        标注 by: agent、pending_user: true

# 5) 组内比来源等级（投票）
RANK = {user_provided: 100, user_approved_web: 60, unapproved_web: 20}
for g in groups:
    m = max(RANK[e.source_rank] for e in g if e 仍在候选池)
    winners[g] = [e for e in g if RANK[e.source_rank] == m]

# 6) 同等级比 priority（5 最高）
for g where len(winners[g]) > 1:
    m = max(e.priority for e in winners[g])
    winners[g] = [e for e in winners[g] if e.priority == m]

# 7) 仍相同比 confidence（0-1）打破平局
for g where len(winners[g]) > 1:
    m = max(e.confidence for e in winners[g])
    winners[g] = [e for e in winners[g] if e.confidence == m]

# 8) 仍无法分出胜负 → conflict（不选边）
for g where len(winners[g]) > 1:
    outcome = "conflict"
    标记 g 内涉及条目为 conflicted
    生成冲突提案 → _review/queue/<id>.md
    回答中显式写出：「库内存在冲突说法，已列入待审队列，请你裁定」

# 第 ⑨ 条 库内 vs 联网冲突（不属于上面八步，是并列的边界细则）
联网结果同样要先过第 ④ 步正误推理（可判谬误 → 标 erroneous，只在答案末尾提示，不入库、不参与裁定）。
库内 user_provided 条目优先；未审核的 web 结果不参与裁定，
只能作为「补充视角」附在答案末尾并标注未审核（[web:<url>] 未审核）。
```

**判定顺序是刚性的**：正误推理 → 来源等级 → priority → confidence。**不许跨步比较**
（例如不能说"这条 confidence 很高所以压过来源等级低的"，也不能跳过第 ④ 步直接比来源等级）。

## 3. 第 ④ 步「正误推理」细则

对每条冲突声明做**可检验**的检查，只有三类证据算数：

1. **内部自洽**：推导 / 计算 / 量纲 / 逻辑有没有矛盾（例：单位不一致、等式推不出来、结论与自身前提冲突）。
2. **与公认基准一致**：教材、标准定义、学科共识、官方文档/规范（例：HTTP 状态码定义、物理常量、语言标准）。
3. **与库内其他高置信条目相容**：库内已有 `source_rank=user_provided` 且被批准的高置信条目是否支持它。

判定规则：

- **能明确判定为谬误** → `verdict=erroneous`，附**具体理由**（推导过程 / 反例 / 量纲 / 定义冲突，必须能被人复核）：
  - **必须显式告知用户，绝不静默丢弃**（不许悄悄不引用就完事）；
  - 生成待审记录让用户最终确认；
  - 标注 `by: agent`、`pending_user: true`。
- **无法判定**（几条都自洽，或只是不同条件 / 版本 / 参数 / 模型假设）→ `verdict=undecidable`，
  进入「来源等级 → priority → confidence」链条（第 ⑤⑥⑦ 步）。
- **优先级缺省**：用户**尚未规定优先级** → agent 自行推理判断，并标注 `by: agent`、`pending_user: true`，
  用户随时可改。

### 硬约束（违反即违规）

- ❌ **禁止仅凭"更常见 / 更符合直觉 / 感觉更权威 / 我印象里是这样"判错**——这不是可检验证据。
- ❌ 禁止把 `undecidable` 硬说成 `erroneous`（判断不了就交给优先级链条，别硬裁）。
- ❌ 禁止静默丢弃：判为 `erroneous` 的条目必须**同时**出现在给用户的显式告知与待审队列里。
- **判错是提案，不是终审**：用户可推翻；用户推翻后立即按用户说法更新库（走正常提案 + 批准流程）。
- 判错不得导致"删条目"：只标记 + 生成待审记录，**原文一律保留**（可回溯）。

## 4. 话术（正误推理相关，照抄）

- 判为谬误时：
  「库内有一条说法我认为是**错的**：<说法>（[src:<id>]）。理由：<推导/反例/量纲/定义冲突>。
   已把它列入待审队列等你确认——**这是我的推理，不是最终结论，你可以推翻我**。」
- 无法判定时：
  「这几条说法我都无法仅凭推理判定对错（可能是不同条件/版本）。按来源等级 → 优先级 → 置信度继续比较。」

## 5. source_rank 数值表（第 ⑤ 步 / 契约 §0 约束 2）

| 来源类型 | source_rank | 说明 |
|---|---|---|
| `user_provided` | **100** | 用户自己提供的资料 / 明确说法 |
| `user_approved_web` | **60** | 联网取得且**用户审核通过**的资料 |
| `unapproved_web` | **20** | 未审核的搜索原文（**不参与裁定**，仅作补充视角） |

来源等级排序即用户要求："用户提供 > 用户审核通过的联网资料 > 未审核的搜索原文"。

## 6. priority / confidence 语义

- `priority` 1-5，**5 最高**，默认 3；**用户尚未规定优先级时由 agent 自行判断**并标 `by: agent`、`pending_user: true`。
- `confidence` 0-1，agent 提案初判，用户可改。代表这条结论本身的可靠度。
- 两者都**不覆盖**来源等级：来源等级是硬优先级，priority/confidence 只在同等级内决胜。

## 7. 实际操作序列（agent 执行）

```
1) engram_search(query=q, scope=<user|project|all>)   # 默认不带 room：房间每 9 条分裂，按房间查会漏（见 engram-usage.md §1）
2) 需要全文/条件时 engram_examine(ids=[...])（≤16 条）
3) 如用户要求联网补齐：web_search → 取结果 → 标 source_rank=unapproved_web（默认，不入库）
4) 对候选集跑上面八步（在心里或写临时脚本算，不用写盘）；第 ④ 步的正误判定必须写下可检验理由
5) engram_assess(batchId, sufficient, evidenceRefs, missing, nextStrategy) 过证据门
6) 按输出格式回答（含 verdict 与依据说明）
```

## 8. 输出示例

### 8.1 resolved（其中一条被推理判错）

```markdown
**结论**：Vite 默认端口是 5173。[src:kb-20261009-0001]

依据：库内 3 条候选聚为同一命题（前端/构建工具/vite-默认端口）。
- 第 ④ 步正误推理：[src:kb-20261008-0005] 说"默认 3000"，与 Vite 官方文档及库内已批准条目冲突，
  且它自述用的是 Vite 1.x 的旧配置键，属定义/版本冲突 → verdict=erroneous（理由：定义冲突 + 版本不适用）。
- 剩余两条按第 ⑤ 步来源等级均为 user_provided（100），第 ⑥ 步 priority 相同（3，by: agent / pending_user: true），
  第 ⑦ 步 confidence 0.9 vs 0.6 → 前者胜出。

判错的那条我也列在这，等你确认：[src:kb-20261008-0005]（已列入待审队列 _review/queue/kb-20261009-0009.md）
2026 年 8 月后的说法存在（valid_from=2026-09-01），尚未生效，请注意。
```

`outcome: resolved`，`chosen_ids: [kb-20261009-0001]`，`conflict_ids: []`。

### 8.2 conflict（八步全平，不选边）

```markdown
**库内存在冲突说法，已列入待审队列，请你裁定。**

- 说法 A（来源等级 100，priority 3，confidence 0.8）：默认端口 5173。[src:kb-20261009-0001]
- 说法 B（来源等级 100，priority 3，confidence 0.8）：默认端口 3000。[src:kb-20261024-0003]
- 第 ④ 步正误推理：两条都自洽、都无版本/条件冲突 → verdict=undecidable。
- 冲突原因：第 ⑤⑥⑦ 步完全并列，无法按规则分出胜负。
- 已生成冲突提案：_review/queue/kb-20261024-0004.md，等你裁定后我再更新库。

---
**补充视角（未审核，不参与裁定）**：某网页说 5173。[web:https://example.com/...]（未审核）
```

`outcome: conflict`，`chosen_ids: []`，`conflict_ids: [kb-20261009-0001, kb-20261024-0003]`。

## 9. 禁止事项（违反即违规）

- ❌ 仅凭"更符合常识 / 更常见 / 我更确定"判错或选边（判错必须有可检验理由）。
- ❌ 静默丢弃被判错的说法（必须显式告知用户 + 建待审记录）。
- ❌ 用未审核的 web 结果推翻库内条目。
- ❌ 隐去失败方（必须把冲突各方都列出来）。
- ❌ 把 `valid_from > now` 的未来条目当现行结论引用。
- ❌ 去掉或改写步骤、增加自定义裁决规则（如"来源等级高就直接跳过后面步骤"——跳过的只是后续比较，不是裁定本身）。
- ❌ 跳过第 ④ 步正误推理直接比来源等级（顺序是刚性的）。
- ❌ 在 conflict 时擅自更新 L2/L3（冲突提案也只是 `proposed`，仍需用户批准）。

## 10. 答案纪律（契约 §5 末）

引用任何条目必须写 `[src:<L1-id>]`，用户能点回原文核对。
库外内容标 `[web:<url>]` 并注明"未审核"。
`by: agent` / `pending_user: true` 的自行判断必须标出来，让用户知道哪部分不是库内已批准结论。
第 ④ 步有任何 `verdict` 时必须写出来：「<id> 的说法我判为谬误 / 无法判定，理由是…（已列入待审队列）」，**不得只字不提**。

## 11. 仲裁自检

- [ ] 我是不是严格按 1→8 步顺序算的（第 ④ 步正误推理有没有跳过）？
- [ ] 我判错时给的是**可检验理由**（推导/反例/量纲/定义冲突），而不是"更常见/更直觉"？
- [ ] 判错的说法我有没有**显式告知用户**并建待审记录？（静默丢弃 = 违规）
- [ ] 我的自行判断有没有标 `by: agent` + `pending_user: true`？
- [ ] 冲突时我有没有选边？（有 → 违规）
- [ ] 未来条目我是不是只提示、没参与裁定？
- [ ] 未审核 web 结果我是不是只放末尾补充视角？
- [ ] 依据说明里我写清了"按第几步胜出 / 按哪条理由判错"吗？
- [ ] conflict 时我建 `_review/queue/` 提案了吗（状态仍是 `proposed`）？
