# dsh-kb-curator

一个 DeepSeek Harness 的 composition bundle：装上之后，它向会话贡献一个只读技能 `kb-curator`，教 agent 维护一套**本地、三层、带人工审核闸门**的知识储备体系。

## 它解决什么问题

Agent 会忘事，而「帮我记住这个」通常等于把一段笔记粘进某个没人回头看的文件里。`dsh-kb-curator` 装进去的不是一个资料堆放目录，而是一套流程：

- 你的资料以 **Markdown 落盘在本地目录树**里（L1），按大类分装，原文只增不改。
- 从资料派生出来的一切——可检索的记忆条目（L2）与按大类成篇的知识页（L3）——**只在提案被批准之后**才写入。在此之前，agent 只能写三个地方：`_inbox/`、`_review/queue/`、`_system/log.jsonl`。
- 每个引用都带 `[src:kb-YYYYMMDD-NNNN]` 标记，指向 L1 原文，结论可以回到出处核对。
- 两份资料说法冲突时，技能规定了一条固定的仲裁顺序；顺序用完仍分不出胜负，agent 报 `conflict`，不替你选边。

知识库本体——一套无外部依赖的 PowerShell 引擎——随包一起发布，见下文「引擎随包发布」。整条链路不调用任何付费嵌入 / 向量 / 检索 API：花钱的只有你本来就在用的那个云端模型。

## 安装

```bash
dsh plugin add dsh-kb-curator
```

这是一个 **bundle**：它把包装进你的 profile，并向 profile 组装文件插入一行插件行 `kb-curator`（见 [`cordis.patch.yml`](cordis.patch.yml)）：

```yaml
- insert:
    - id: kb-curator
      name: 'dsh-kb-curator'
```

本 bundle 没有任何配置项。行挂载着，技能就注册着；禁用或删掉这一行即卸载技能。

peer 依赖（由 Harness 解析，本包不负责安装）：

| 包 | 版本范围 |
|---|---|
| `@deepseek-ai/cordis` | `~4.0.4` |
| `@deepseek-ai/dsh-skill` | `>=0.1.0-rc.1 <0.2.0-0` |

需要 Node.js `^22.19.0 || >=24.0.0`。

## 首次使用

插件只发布引擎，**不会**替你建库——库放哪儿由你选。

1. **找到已安装 bundle 的技能目录。** 技能的资源基目录是包内的 `assets/kb-curator/`（`lib/index.js` 会把这个路径交给模型），里面有 `SKILL.md`、`references/` 和 `engine/`。
2. **把整个 `engine/` 目录复制**到你选定的知识库根目录。引擎是自定位的——`kb.ps1` 用 `$PSScriptRoot`——所以 `engine/` 复制到哪儿，哪儿就是知识库根目录。`kb.config.json` 里的 `root` 只是给人看的说明字段，程序不读它。

   ```powershell
   $KB = "D:\KnowledgeBase"                     # 你选定的根目录
   Copy-Item -Recurse "<技能基目录>\engine\*" $KB
   ```

   必须**复制完整**：`init` 之前引擎就需要 `_system/` 里的规范文件和 `_templates/` 模板。

3. **建骨架**——创建目录树和每个大类一张知识页骨架。`init` 是幂等的：只补缺失项，绝不覆盖。

   ```powershell
   & "$KB\kb.cmd" init
   ```

4. **随时看状态**——只读输出：库根、磁盘剩余空间与两条阈值线、待审 / 已批准 / 已驳回提案数、各层文件数、规范文件是否齐备。不写日志、不改任何文件。

   ```powershell
   & "$KB\kb.cmd" status
   ```

每次收料或批量写入之前都先跑 `status`，理由见「磁盘守卫」。

## 仓库结构

```text
dsh-kb-curator/
├─ package.json                  npm 清单：声明 dsh.bundle.patch 与 peer 依赖
├─ cordis.patch.yml              组装层：插入一行 `kb-curator`
├─ lib/
│  └─ index.js                   注册这个 bundled 只读技能 provider
├─ scripts/
│  └─ check-assets.mjs           仓库自检脚本（见「开发与自检」）
├─ assets/kb-curator/            技能的资源基目录
│  ├─ SKILL.md                   技能正文：frontmatter 里的 name + description
│  ├─ references/                7 份按需加载的参考文档
│  │  ├─ contract.md             冻结契约：整套设计的唯一事实来源
│  │  ├─ arbitration.md          冲突仲裁八步 + 可执行伪码
│  │  ├─ architecture.md         三层架构、目录布局、L1 frontmatter 字段
│  │  ├─ engram-usage.md         engram 工具 schema、路由、证据门
│  │  ├─ kb-cli.md               引擎命令说明与三种调用方式的实测结果
│  │  ├─ learning.md             消化层五要素与知识页结构
│  │  └─ review-workflow.md      五状态流转、提案字段、批准后谁做什么
│  └─ engine/                    把整个目录复制到你的知识库根目录
│     ├─ kb.ps1                  真正实现
│     ├─ kb.cmd                  ASCII 包装器，唯一推荐入口
│     ├─ kb.config.json          大类清单、默认值、付费开关、磁盘阈值
│     ├─ README.md               引擎自己的使用说明
│     ├─ _system/
│     │  ├─ taxonomy.yml         8 大类 → 子类 + 触发关键词
│     │  ├─ priority.yml         来源等级 100/60/20、priority 1-5、confidence 0-1
│     │  ├─ arbitration.md       冻结的仲裁算法
│     │  ├─ entry-schema.md      L1 frontmatter 与 L2/L3 格式规范
│     │  ├─ review-workflow.md   五状态流转与安全阀
│     │  ├─ learning.md          「消化产物」必须包含什么
│     │  └─ log.jsonl            只追加的操作日志（随包发布时为空）
│     └─ _templates/
│        ├─ source-note.md
│        ├─ memory-entry.md
│        ├─ knowledge-page.md
│        └─ review-proposal.md
├─ LICENSE                       MIT
├─ README.md                     英文版（主文档）
└─ README.zh.md                  本文件
```

## 三层架构

| 层 | 放什么 | 在哪 | 谁能写 |
|---|---|---|---|
| **L1 原文库** | 资料原文逐字 + 固定 frontmatter。只增不改。 | `library/<大类>/<子类>/<yyyy-mm-dd>-<slug>.md` | 只有 `kb.cmd approve` |
| **L2 检索层** | 一句话命题（fact / preference / decision / episode / skill），带 `[src:...]` 标记，可检索 | engram SQLite 库，经 `engram_*` 工具 | agent，在你批准之后 |
| **L3 知识页** | 每个大类一张页：按主题的消化综述 + 索引 + 待裁定冲突 | `pages/<大类>.md` | agent，在你批准之后 |

设计原则：原文留在 L1（不花钱、不会丢），L2 只存提炼后的命题，L3 只放消化后的理解与索引。知识页**永远不接收整段原文**——如果一段内容被整段搬进 L3，那它就该留在 L1 并只放一个链接指过去。单张页超过约 200 行时，细节下沉回 L1/L2，页面只留结论与索引。

初始 8 大类：`技术工程`、`产品业务`、`学术研究`、`生活健康`、`财务投资`、`人文社科`、`工具流程`、`未分类`（兜底）。子类目录**不会预建**：第一条该子类的资料被批准时才出现。`init` 只建 8 个顶层大类目录——这是设计如此，不是漏建。

### 审核闸门

```text
inbox ──agent 写提案──▶ proposed ──你批准──▶ approved ──入库──▶ indexed
                          │
                          ├──你驳回──▶ rejected
                          └──你要改──▶ needs_edit ──agent 改完──▶ proposed
```

状态不是 `approved` 的条目，绝对不允许进入 L2 或 L3，没有「先临时写进去、等用户批准」这条路。条目处于 `proposed` / `rejected` / `needs_edit` 时，agent 只能写：

- `_inbox/` —— 收料副本与它的 `.meta.md` 元数据
- `_review/queue/` —— 等你裁定的提案
- `_system/log.jsonl` —— 只追加的操作日志

一份提案必须写清：原文摘要、建议分类、建议优先级、置信度、**打算写入 L2 的条目正文**、**打算对 L3 做的改动**。批准时 `kb.cmd approve` 只做三件事：落 L1、归档提案、记日志；之后由 agent 完成 L2 写入、L3 更新和最后的状态登记。

### 冲突仲裁

检索到的命题互相矛盾时，按固定顺序处理。聚类与过滤之后依次是：

1. **同领域过滤**——只保留与提问的 category/subcategory 相关的条目。
2. **时效过滤**——`valid_until` 已过的剔除；`valid_from` 尚未到的标为「未来条目」，不参与裁定，但要在回答里提示。
3. **正误推理**——逐条做**可检验**的检查：内部自洽（推导、计算、量纲、逻辑）、与教材 / 标准 / 学科共识一致、与库内其他高置信条目相容。能明确判定为谬误的，**显式告诉你**并附具体理由，同时生成待审记录交你确认；**绝不静默丢弃**。
4. **再比来源等级**——`user_provided` = 100 > `user_approved_web` = 60 > `unapproved_web` = 20。
5. **再比 `priority`**（1–5，5 最高）。
6. **再比 `confidence`**（0–1）。
7. **仍打平**——报 `conflict`，不选边，把相关条目标记为冲突，并在待审队列里生成一条冲突提案。

有两条约束使它不只是打分比较：不许仅凭「更常见 / 更符合直觉 / 感觉更权威」判某条说法出错——必须有可检验的理由；未审核的联网结果也不能推翻库内条目，只能作为明确标注「未审核」的补充视角附在末尾。

仲裁顺序是冻结的，agent 不得自行增删或调换。

### 引用可回溯

- 引用库内内容必须带 `[src:kb-YYYYMMDD-NNNN]`，指向 L1 的 id。
- 库外或尚未审核的内容标 `[web:<url>]`，并且**不参与仲裁**。
- 没有 `[src:...]`（或等价的「来源：kb-...」）标记的 L2 条目不得写入。

## 引擎随包发布

`assets/kb-curator/engine/` 里是一个单文件 PowerShell 引擎：无外部依赖、不联网、不引入 LLM 依赖，关键操作幂等，而且从不销毁数据——`kb.ps1` 只移动和追加，不删除你的资料，也不会覆盖已有的 L1 卡片（同名时加 `-2` 后缀另存）。

引擎不写记忆条目。`kb.cmd approve` 只处理文件与登记，写 L2 是 agent 通过 `engram_*` 工具的活儿。引擎也从不引入任何 LLM 依赖，这正是它免费、可离线跑的原因。

### 命令速查

```bat
kb.cmd init
kb.cmd status
kb.cmd add -Path "D:\dl\some-file.md" -Category "CATEGORY"
kb.cmd list-queue
kb.cmd show ID
kb.cmd approve ID
kb.cmd reject  ID -Reason "unreliable source"
kb.cmd search  "vite port"
kb.cmd page    "CATEGORY"
kb.cmd log -Tail 20
```

`ID` 形如 `kb-YYYYMMDD-NNNN`；`CATEGORY` 是某个大类名。`add` 还接受 `-Subcategory`、`-Title`、`-SourceType`、`-Url`、`-Priority`、`-Confidence`、`-PropositionKey`、`-Force`；`approve` 接受 `-UpdatePage`；`page` 接受 `-Create`。不带参数时的默认命令是 `help`。

| 命令 | 作用 |
|---|---|
| `status` | 只读汇报：库根、磁盘剩余空间与两条阈值线、提案计数、各层计数、规范文件齐备性。不写日志。 |
| `init` | 建目录树与知识页骨架。幂等；只补缺失项，绝不覆盖。同时打印剩余空间。 |
| `add -Path <文件> [...]` | 把文件收进 `_inbox/` 并生成初始元数据：分配 id、算 `content_hash` 并拒绝重复（确实要再收一份才用 `-Force`）。**不生成提案**。 |
| `list-queue` | 列出 `_review/queue/` 里的待审提案；提案缺必填字段时会给出警告。 |
| `show <id>` | 查看提案 / 已归档提案 / L1 原文卡。 |
| `approve <id> [-UpdatePage]` | 落 L1、归档提案、记日志，并打印 agent 待办。默认不动 `pages/`；加 `-UpdatePage` 才机械追加一行索引。 |
| `reject <id> -Reason "..."` | 归档提案并保留你的驳回理由，材料移入 `_inbox/_rejected/`。理由必填。 |
| `search <query>` | 在 L1、L3、待审队列里做**字面**检索，用来定位原文；语义检索不走这里。 |
| `page [<大类>] [-Create]` | 查看某大类知识页；不带参数则列出全部。 |
| `log [-Tail N]` | 查看操作日志（默认 20 条）。 |
| `help` | 用法帮助。 |

引擎**故意没有 `remove` / `del`**：这套知识库只新增、只移动，永不删除你的资料。

### 磁盘守卫

阈值在 `kb.config.json` 的 `storage` 里，每次收料前自动检查。

| 线 | 配置项 | 默认 | 行为 |
|---|---|---|---|
| 提醒线 | `warn_free_gb` | `20` | `add` 打印 `[磁盘告警]`，**仍然放行**本次收料，agent 必须立刻转告你并给出清理建议。exit 0。 |
| 拒绝线 | `block_free_gb` | `5` | `add` 打印「已拒绝本次收料」，exit 1，不写 `_inbox/`。agent 不得绕过。 |

改这两个数字即时生效，无需重跑 `init`。`init` 也会打印剩余空间，`status` 可随时只读查询。推荐的省空间顺序：先 `_staging/`（可重建的转换中间产物），再 `_sources/` 里已消化完的大文件，`library/` 原文最后动。

### 成本

随包的 `kb.config.json` 里 `paid_services_allowed: false`，并列出了禁止的服务。花钱的只有你主动调用的云端模型，其余全本地、免费，原文只存在你自己的磁盘上。

## 平台限制

装之前请先确认这几条：

- **引擎是 Windows 专用的。** `kb.ps1` 面向 Windows PowerShell 5.1，`kb.cmd` 也是通过 `powershell.exe` 调用它。脚本按 5.1 编写，不依赖 PowerShell 7。
- **`kb.cmd` 是唯一推荐入口。** 在会话里直接调用 `kb.ps1` 可能失败：

  ```text
  AuthorizationManager check failed. (PSSecurityException)
  ```

  这是**会话执行策略**问题，**不是目录或 ACL 问题**：当前有效执行策略不放行未签名的 `.ps1`。以子进程方式、显式带绕过参数调用是能过的——包装器内部做的就是这件事：

  ```bat
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0kb.ps1" %*
  ```

  确需直调 `kb.ps1` 时，自己带上 `-ExecutionPolicy Bypass`。因为包装器永远会带，调用方不必再关心执行策略。
- **非 Windows 用户目前无法运行引擎。** 包里没有与 shell 无关的、或 POSIX 的入口。技能正文与参考文档在任何平台都能读，但本 README 里的 `kb.cmd` 命令需要 Windows。
- **编码规则是硬要求。** `kb.ps1` 必须以 **UTF-8 with BOM** 保存，否则 Windows PowerShell 5.1 会按 ANSI 读，中文全乱。`kb.cmd` 必须保持**纯 ASCII**，因为 `cmd.exe` 用 OEM 代码页读 `.cmd`。两条都由自检脚本强制。

## 可选依赖：engram

L2 由 `@kenz1117/dsh-engram` 提供，它**不是**本包的依赖。想要可检索的记忆层就另外装：

```bash
dsh plugin add @kenz1117/dsh-engram
```

| 装了吗 | 你会得到 |
|---|---|
| 装了 | L1 + L2 + L3：提案、审核、可检索命题、按大类的知识页。 |
| 没装 | L1 + L3。收料、审核、批准、L1 落盘、知识页全都照常，只是提案里的 L2 部分没地方可写，检索层退化成没有。 |

如果某个正在运行的会话的工具清单里看不到 `engram_*` 工具，说明该会话是在插件装上之前启动的——重启 DSH 桌面端或新建会话。技能明确禁止用文件模拟 engram 写入。

## 故障排查

**装了却看不到技能，或者看到的是自己的同名技能。**
本 bundle 以最低优先级注册技能——bundled rank **600**。磁盘上任何同名技能都会盖过它：

| 来源根目录 | 优先级 |
|---|---|
| 项目 `.dsh/skills` | 100 |
| 项目 `.agents/skills` | 200 |
| custom 根目录 | 300 |
| `~/.dsh/skills` | 400 |
| `~/.agents/skills` | 500 |

这是设计行为：如果你本来就在本地维护自己的 `kb-curator`，本地版优先，本包的条目只是在目录里被遮蔽，而不是重复出现。想让 bundled 版生效，就删掉或改名本地那份。

**`AuthorizationManager check failed.`**
你直接调了 `kb.ps1`。改调 `kb.cmd`，或者在自己的 `powershell.exe` 调用里加 `-ExecutionPolicy Bypass`。详见「平台限制」。

**`[警告] 缺少规范文件：…`**
引擎目录没复制全。`init` 只建目录和知识页骨架，**不重建规范文件**。重新完整复制 `engine/`（含 `_system/` 与 `_templates/`），再跑 `kb.cmd status`，确认输出里写着规范文件齐备。

**`[磁盘告警] …本次收料继续，但请立即提醒用户清理磁盘`**
知识库所在盘剩余空间已低于 `storage.warn_free_gb`（默认 20 GB），本次收料仍然完成。请清理，从 `_staging/` 开始。如果提示是**拒绝收料**，说明剩余空间低于 `storage.block_free_gb`（默认 5 GB），命令 exit 1 且什么都没写——先腾空间，不要改写到别的盘绕过。

**`list-queue` 是空的。**
正常。`add` 只收料登记，从不生成提案；提案要 agent 读完收料副本之后才写。

**`approve` 报缺 `inbox_path`。**
提案缺了必填的 frontmatter 字段。`approve` 只读 frontmatter——写在正文里等于没写，而脚本遇到缺字段是**静默降级**、不报错。按 `_templates/review-proposal.md` 补齐字段，`list-queue` 是唯一会给出警告的地方。

**L1 里同一份资料出现两张卡（`…-2.md`）。**
有人在批准之前先自己写了一份 L1。L1 一律由 `approve` 落盘；遇同名时脚本加 `-2` 后缀而不是覆盖，重复卡就是这么来的。保留由 `approve` 写出来的那张。

**`kb.cmd` 报一堆 `'xxx' is not recognized as an internal or external command`。**
`kb.cmd` 里混进了非 ASCII 内容。保持该文件纯 ASCII。

**中文乱码。**
`kb.ps1` 的 UTF-8 BOM 丢了；重新以「UTF-8 带 BOM」保存。

## 开发与自检

仓库自带资产契约自检，**不需要 `npm install`** 就能在全新 clone 里跑——它只用 `node:` 内建模块：

```bash
node scripts/check-assets.mjs
```

它检查：

1. **技能元数据一致**——`SKILL.md` 的 frontmatter 能解析，且 `name` / `description` 与 `lib/index.js` 里的 `SKILL_NAME` / `SKILL_DESCRIPTION` 逐字节一致。这里漂移是无声的：目录广告的触发词会和技能正文说的不一样。
2. **资产齐备**——每份参考文档、每个引擎文件都存在且非空。
3. **无本机路径泄漏**——任何随包资产都不含只在作者机器上才成立的路径。
4. **编码规则**——`kb.ps1` 带 UTF-8 BOM、`kb.cmd` 纯 ASCII、其余随包资产都不带 BOM。
5. **引擎骨架自洽**——`kb.config.json` 能解析、大类非空、提醒线高于拒绝线，`_system/log.jsonl` 随包为空，`cordis.patch.yml` 挂载的包名与 `package.json` 里声明的一致。

`npm test` 与 `npm run check` 都指向同一个脚本。

仓库里目前没有 CI workflow——提交前请在本地跑这个自检。要添加 `.github/workflows/` 需要带 `workflow` scope 的 token，这就是自检尚未自动化的原因。

## 许可

MIT —— Copyright (c) 2026 Mark-mph。见 [`LICENSE`](LICENSE)。

## 相关链接

- 仓库：<https://github.com/Mark-mph/dsh-kb-curator>
- 问题反馈：<https://github.com/Mark-mph/dsh-kb-curator/issues>
- 引擎使用说明：[`assets/kb-curator/engine/README.md`](assets/kb-curator/engine/README.md)
- 技能正文：[`assets/kb-curator/SKILL.md`](assets/kb-curator/SKILL.md)
