# L2 记忆条目模板（memory-entry.md）

> 这不是文件，是**写入 engram 的一条 content**。一条 L1 原文卡通常产出 1-3 条。
> 规则见 `_system/entry-schema.md` §2。

## 必填字段

| 字段 | 取值 |
|---|---|
| `content` | `<命题>：<结论>。条件：<适用条件>。来源：<L1-id>。 [src:<L1-id>]` |
| `kind` | `fact` / `preference` / `decision` / `episode` / `skill`（**英文，只写这个**） |
| `room` | **不要传**。room 是 engram 自动排桩的**中文房名**（`事实厅`/`偏好阁`/`决策堂`/`往事廊`/`技法坊`），每满 9 条分裂出 `-2`；传英文 kind 匹配不上任何房间 |
| `scope` | `user`（跨项目通用与用户偏好）/ `project`（项目相关） |
| `importance` | 0-1，用户强调的给 0.7+，一般资料 0.4-0.6 |

## 模板

```
content: <命题>：<结论>。条件：<适用条件>。来源：<L1-id>。 [src:<L1-id>]
kind: fact
scope: user
importance: 0.5
```

## 示例

```
content: Vite 开发服务器默认端口：5173。条件：未在 vite.config 中显式指定 server.port。来源：kb-20261009-0001。 [src:kb-20261009-0001]
kind: fact
scope: user
importance: 0.5
```

> `room` 不是 `kind` 的同义词：`engram_save` 只收英文 `kind`，房名由 engram 自己排桩。
> 检索侧同理——`engram_search` 的 `room` 只认中文房名，知识库**默认不带 room**（全库查），详见 `_system/entry-schema.md` §2.1。

## 保存前自检（缺一不可）

- [ ] content 里有 `[src:<L1-id>]`，且 L1-id 在 `library/` 中真实存在
- [ ] 用户已明确批准这条提案
- [ ] engram 相似度告警出现时，改用 `engram_update` 归并，不新建重复条目
- [ ] scope 选对（通用→user；项目→project）
