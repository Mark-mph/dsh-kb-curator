---
<!-- 待审提案模板（review-proposal.md）
     落点：_review/queue/<id>.md（用户批准后移入 _review/approved/，驳回移入 _review/rejected/）
     批准前 agent 禁止写 library/、engram、pages/。 -->
id: kb-20260101-0001
title: "<标题>"
category: 未分类
subcategory: 通用
source_type: user_file
source_url: ""
fetched_at: ""
added_at: 2026-01-01T00:00:00+08:00
content_hash: "<sha256>"
status: proposed
priority: 3
confidence: 0.8
valid_from: ""
valid_until: ""
supersedes: []
tags: []
proposition_key: "未分类/通用/<slug>"
source_rank: 100
inbox_path: "_inbox/kb-20260101-0001-<slug>.md"
origin_path: "<用户原始文件路径>"
# ↓ 这三个字段 kb.ps1 会从提案 frontmatter 读出来，直接拼成给 agent 的 engram_save 参数
l2_kind: fact        # 英文 fact/preference/decision/episode/skill（**不是 room**；房名由 engram 自动排桩）
l2_scope: user       # user（跨项目通用/用户偏好）或 project（项目相关）
l2_content: "<命题>：<结论>。条件：<适用条件>。来源：kb-20260101-0001。 [src:kb-20260101-0001]"
---

# 待审提案 kb-20260101-0001

## 1. 原文摘要

<3-5 句。原文全文见 §7 指向的 L0 副本，批准后原样落盘 L1。>

## 2. 建议分类

- 大类：未分类
- 子类：通用
- 依据：<命中的 taxonomy 关键词 / 无命中则说明归入未分类>

## 3. 建议优先级 / 置信度

- priority：3（1-5，5 最高，用户可改）
- confidence：0.8（0-1，用户可改）
- source_rank：100（user_file；user_provided=100 / user_approved_web=60 / unapproved_web=20）

## 4. 将要写入 engram 的条目（L2，批准后执行）

- kind：fact（**英文**；engram 自动排桩到中文房名「事实厅」，每满 9 条分裂出「事实厅-2」）
- ⚠️ 不要传 `room`：`room` 只认中文房名，传英文匹配不上任何房间；检索时**默认也不带 room**（全库查）
- scope：user
- content：`<命题>：<结论>。条件：<适用条件>。来源：kb-20260101-0001。 [src:kb-20260101-0001]`

## 5. 将要更新的知识页 diff（L3）

- 目标：`pages/未分类.md` → 「已入库条目索引」追加一行：
  `- [kb-20260101-0001] <标题> — <一句话结论> [src:kb-20260101-0001]`

## 6. 待用户裁定

- 回复「批准 kb-20260101-0001」→ 入库（L1 + L2 + L3）
- 回复「驳回 kb-20260101-0001，理由…」→ 归档到 `_review/rejected/`
- 回复「要改 kb-20260101-0001，改成…」→ agent 改完重新提交待审

## 7. 原文位置

- L0 副本：`_inbox/kb-20260101-0001-<slug>.md`
- 用户原文件：`<路径>`（**始终不动**，系统只读副本）
- 落盘目标（批准后）：`library/未分类/通用/2026-01-01-<slug>.md`
