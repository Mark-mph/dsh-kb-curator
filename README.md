# dsh-kb-curator

A DeepSeek Harness composition bundle that contributes one read-only skill, `kb-curator`, teaching an agent to maintain a local, three-layer knowledge base with a mandatory human review gate.

## What it solves

Agents forget, and "let me remember this" usually means pasting a note into a file that nobody ever reviews. `dsh-kb-curator` installs a discipline instead of a dump folder:

- Your source material lands as **Markdown in a local directory tree** (L1), grouped by category, and is never edited in place.
- Anything derived from it — searchable memory entries (L2) and per-category knowledge pages (L3) — is written **only after you approve a proposal**. Until then the agent may write exactly three places: `_inbox/`, `_review/queue/`, and `_system/log.jsonl`.
- Every quoted conclusion carries a `[src:kb-YYYYMMDD-NNNN]` marker back to the original document, so a claim can be checked against its source.
- When two sources disagree, the skill defines a fixed arbitration order; if the order runs out, the agent reports a conflict instead of picking a side.

The knowledge base itself, a dependency-free PowerShell engine, ships inside this package (see [Bundled engine](#bundled-engine)). Nothing in the pipeline calls a paid embedding, vector, or search API — the cloud model you are already talking to is the only line item.

## Install

```bash
dsh plugin add dsh-kb-curator
```

This is a **bundle**: it installs the package into your profile and inserts one plugin row, `kb-curator`, into the profile composition (see [`cordis.patch.yml`](cordis.patch.yml)):

```yaml
- insert:
    - id: kb-curator
      name: 'dsh-kb-curator'
```

The bundle declares no configuration options. The skill is registered whenever the row is mounted; disable or remove the row to drop it.

Peer dependencies (resolved by the Harness, not installed by this package):

| Package | Range |
|---|---|
| `@deepseek-ai/cordis` | `~4.0.4` |
| `@deepseek-ai/dsh-skill` | `>=0.1.0-rc.1 <0.2.0-0` |

Node.js `^22.19.0 || >=24.0.0` is required.

## First run

The plugin ships the engine but does **not** create a knowledge base for you. You choose the directory.

1. **Find the installed bundle's skill directory.** The skill's resource base is `assets/kb-curator/` inside the installed package (`lib/index.js` hands that path to the model). It contains `SKILL.md`, `references/`, and `engine/`.
2. **Copy the whole `engine/` directory** into the folder you want to use as your knowledge base root. The engine is self-locating — `kb.ps1` uses `$PSScriptRoot` — so wherever `engine/` lands becomes the root. The `kb.config.json` `root` field is documentation for humans; the program does not read it.

   ```powershell
   $KB = "D:\KnowledgeBase"                     # your chosen root
   Copy-Item -Recurse "<skill-base>\engine\*" $KB
   ```

   Copy `engine/` **in full**. The engine needs its `_system/` specification files and `_templates/` before `init` has ever run.

3. **Initialize the layout** — creates the directory tree and one skeleton knowledge page per category. `init` is idempotent: it only creates what is missing and never overwrites.

   ```powershell
   & "$KB\kb.cmd" init
   ```

4. **Check status at any time** — a read-only report of the root, free disk space against both thresholds, pending/approved/rejected proposal counts, per-layer file counts, and whether the specification files are complete. It writes no log entries and changes no files.

   ```powershell
   & "$KB\kb.cmd" status
   ```

Run `status` before every ingest or bulk write; see [Disk guard](#disk-guard).

## Repository layout

```text
dsh-kb-curator/
├─ package.json                  npm manifest; declares dsh.bundle.patch and peer deps
├─ cordis.patch.yml              the composition layer: one inserted `kb-curator` row
├─ lib/
│  └─ index.js                   registers the bundled read-only skill provider
├─ scripts/
│  └─ check-assets.mjs           repository self-check (see Self-check)
├─ assets/kb-curator/            the skill's resource base
│  ├─ SKILL.md                   skill body; frontmatter name + description
│  ├─ references/                seven reference documents loaded on demand
│  │  ├─ contract.md             the frozen contract: the design's source of truth
│  │  ├─ arbitration.md          conflict arbitration, eight steps with pseudocode
│  │  ├─ architecture.md         three layers, directory layout, L1 frontmatter fields
│  │  ├─ engram-usage.md         engram tool schemas, routing, evidence gate
│  │  ├─ kb-cli.md               engine command reference and measured invocation results
│  │  ├─ learning.md             the five-element digestion layer and page structure
│  │  └─ review-workflow.md      five states, proposal fields, who writes what after approval
│  └─ engine/                    copy this whole directory to your knowledge base root
│     ├─ kb.ps1                  the implementation
│     ├─ kb.cmd                  ASCII wrapper and the recommended entry point
│     ├─ kb.config.json          categories, defaults, paid-service switch, disk thresholds
│     ├─ README.md               the engine's own manual
│     ├─ _system/
│     │  ├─ taxonomy.yml         8 categories -> subcategories + trigger keywords
│     │  ├─ priority.yml         source ranks 100/60/20, priority 1-5, confidence 0-1
│     │  ├─ arbitration.md       the frozen arbitration algorithm
│     │  ├─ entry-schema.md      L1 frontmatter and L2/L3 formats
│     │  ├─ review-workflow.md   five-state flow and the safety valve
│     │  ├─ learning.md          what a "digested" knowledge unit must contain
│     │  └─ log.jsonl            append-only operation log (ships empty)
│     └─ _templates/
│        ├─ source-note.md
│        ├─ memory-entry.md
│        ├─ knowledge-page.md
│        └─ review-proposal.md
├─ LICENSE                       MIT
├─ README.md                     this file
└─ README.zh.md                  Simplified Chinese version
```

## The three layers

| Layer | What it holds | Where it lives | Who may write it |
|---|---|---|---|
| **L1 — source library** | The original document, verbatim, with a fixed frontmatter block. Only ever appended. | `library/<category>/<subcategory>/<yyyy-mm-dd>-<slug>.md` | `kb.cmd approve` only |
| **L2 — retrieval layer** | One-sentence propositions (fact / preference / decision / episode / skill) with a `[src:...]` marker, searchable. | engram SQLite store, via the `engram_*` tools | the agent, after your approval |
| **L3 — knowledge pages** | One page per category: a synthesis per topic plus an index and any unresolved conflicts. | `pages/<category>.md` | the agent, after your approval |

Design rule: originals stay in L1 (free, lossless), L2 holds only distilled propositions, L3 holds only digested understanding and pointers. A knowledge page never receives a copied paragraph — if content is being moved wholesale into L3, it belongs in L1 with a link. When a page grows past roughly 200 lines, detail moves back down to L1/L2 and the page keeps the summary and the index.

The eight initial categories are `技术工程`, `产品业务`, `学术研究`, `生活健康`, `财务投资`, `人文社科`, `工具流程`, and `未分类` (the fallback). Subcategory directories are **not** pre-created: they appear the first time a document of that subcategory is approved. `init` creating only the eight top-level category directories is intentional.

### The review gate

```text
inbox ──agent writes a proposal──▶ proposed ──you approve──▶ approved ──ingested──▶ indexed
                                     │
                                     ├──you reject──▶ rejected
                                     └──you request changes──▶ needs_edit ──agent──▶ proposed
```

Anything whose status is not `approved` must not reach L2 or L3. There is no "write it temporarily and wait for approval" path. While an entry is `proposed`, `rejected`, or `needs_edit`, the agent may write only:

- `_inbox/` — the incoming copy and its `.meta.md` metadata
- `_review/queue/` — the proposal awaiting your decision
- `_system/log.jsonl` — the append-only operation log

A proposal must state the source summary, the suggested category, the suggested priority, a confidence value, the exact L2 entry text it intends to write, and the intended L3 change. On approval, `kb.cmd approve` does three things and no more: it writes L1, archives the proposal, and logs the decision — then the agent performs the L2 write, the L3 update, and the final status/index bookkeeping.

### Conflict arbitration

When retrieved propositions disagree, they are resolved in a fixed order. After clustering and filtering, the order is:

1. **Filter by the same domain** — only entries about the question's category/subcategory survive.
2. **Filter by validity** — entries past `valid_until` are dropped; entries whose `valid_from` is still in the future are surfaced as "not yet in effect" and take no part in the decision.
3. **Reason about correctness** — each claim is checked against something testable: internal consistency (derivation, arithmetic, units, logic), agreement with textbooks/standards/consensus, and compatibility with other high-confidence entries. A claim that can be shown wrong is told to you explicitly with the specific reason, and a record is opened for review. It is never silently discarded.
4. **Then compare source rank** — `user_provided` = 100 > `user_approved_web` = 60 > `unapproved_web` = 20.
5. **Then compare `priority`** (1–5, 5 highest).
6. **Then compare `confidence`** (0–1).
7. **Still tied** — the agent reports `conflict`, picks no side, marks the entries conflicted, and opens a conflict proposal in the review queue.

Two constraints make this more than a score comparison: a claim may not be judged wrong merely because it is less common, less intuitive, or feels less authoritative — there must be a testable reason; and unapproved web results never override a library entry. They may appear only as an explicitly labelled "unverified, supplementary view".

The arbitration order is frozen and must not be extended or reordered by the agent.

### Provenance markers

- Quoted library content must carry `[src:kb-YYYYMMDD-NNNN]`, pointing at the L1 id.
- Content outside the library, or not yet approved, is marked `[web:<url>]` and **does not participate in arbitration**.
- An L2 entry without a `[src:...]` (or an equivalent `来源：kb-...`) marker is not eligible to be written.

## Bundled engine

`assets/kb-curator/engine/` holds a single-file PowerShell engine: no external dependencies, no network calls, no LLM dependency, idempotent where it matters, and never destructive — `kb.ps1` moves and appends, it does not delete your material and it will not overwrite an existing L1 card (a name collision gets a `-2` suffix instead).

The engine does not write memory entries. `kb.cmd approve` handles files and bookkeeping only; writing L2 is the agent's job through the `engram_*` tools. The engine also never introduces an LLM dependency, which is what keeps the whole thing free and runnable offline.

### Command reference

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

`ID` is `kb-YYYYMMDD-NNNN`; `CATEGORY` is a category name. `add` additionally accepts `-Subcategory`, `-Title`, `-SourceType`, `-Url`, `-Priority`, `-Confidence`, `-PropositionKey`, and `-Force`; `approve` accepts `-UpdatePage`; `page` accepts `-Create`. `help` is the default command.

| Command | Purpose |
|---|---|
| `status` | Read-only report: root, free disk space and both thresholds, proposal counts, per-layer counts, specification completeness. Writes no log entry. |
| `init` | Create the directory tree and the knowledge-page skeletons. Idempotent; only creates what is missing, never overwrites. Also prints free space. |
| `add -Path <file> [...]` | Ingest a file into `_inbox/` and generate its initial metadata. Assigns the id, computes `content_hash` and refuses a duplicate (use `-Force` to ingest a second copy deliberately). Does **not** create a proposal. |
| `list-queue` | List pending proposals in `_review/queue/`. Warns about proposals missing required fields. |
| `show <id>` | Show a proposal, an archived proposal, or an L1 card. |
| `approve <id> [-UpdatePage]` | Write L1, archive the proposal, log the approval, and print the agent's remaining to-dos. `pages/` is untouched unless `-UpdatePage` appends a mechanical index line. |
| `reject <id> -Reason "..."` | Archive the proposal with your reason and move the material to `_inbox/_rejected/`. The reason is required. |
| `search <query>` | Literal text search over L1, L3, and the pending queue. Locates source documents; it is not the semantic retrieval path. |
| `page [<category>] [-Create]` | Show one knowledge page, or list all pages when no category is given. |
| `log [-Tail N]` | Show the operation log (20 entries by default). |
| `help` | Usage. |

There is deliberately **no `remove`/`del` command**: this knowledge base only adds and moves, and never deletes your material.

### Disk guard

Thresholds live in `kb.config.json` under `storage` and are checked before every ingest.

| Line | Key | Default | Behaviour |
|---|---|---|---|
| Warning | `warn_free_gb` | `20` | `add` prints `[磁盘告警]`, still accepts the document, and the agent is required to tell you immediately and suggest cleanup. Exit code 0. |
| Block | `block_free_gb` | `5` | `add` prints `已拒绝本次收料` and exits 1 without writing to `_inbox/`. The agent must not work around it. |

Edit the two numbers to change them; the change takes effect immediately, with no re-`init`. `init` also prints free space, and `status` reports it on demand. The intended cleanup order is `_staging/` (rebuildable conversion intermediates) first, then large completed originals under `_sources/`, and library originals last.

### Cost

The shipped `kb.config.json` sets `paid_services_allowed: false` and lists forbidden services. Only the cloud model you invoke spends money; everything else is local and free, and your originals stay on your own disk.

## Platform support

Be aware of this before installing:

- **The engine is Windows-only.** `kb.ps1` targets Windows PowerShell 5.1, which is what `kb.cmd` invokes through `powershell.exe`. It is written for 5.1 and does not rely on PowerShell 7.
- **`kb.cmd` is the only recommended entry point.** Calling `kb.ps1` directly from a session can fail with:

  ```text
  AuthorizationManager check failed. (PSSecurityException)
  ```

  This is a **session execution-policy** issue, not a directory or ACL problem: the effective policy does not permit unsigned `.ps1` files. Invoking the script as a child process with an explicit bypass flag succeeds, which is exactly what the wrapper does internally:

  ```bat
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0kb.ps1" %*
  ```

  If you must call `kb.ps1` directly, pass `-ExecutionPolicy Bypass` yourself. Because the wrapper always does, callers never have to think about policy.
- **Non-Windows users cannot run the engine at present.** There is no shell-independent or POSIX entry point in the package. The skill body and reference documents are readable anywhere, but the `kb.cmd` commands in this README require Windows.
- **Encoding is load-bearing.** `kb.ps1` must be saved as UTF-8 **with** BOM, or Windows PowerShell 5.1 reads it as ANSI and mangles the non-ASCII text. `kb.cmd` must stay **pure ASCII**, because `cmd.exe` reads `.cmd` files in the OEM code page. Both rules are enforced by the self-check.

## Optional dependency: engram

Layer 2 is provided by `@kenz1117/dsh-engram`, which is **not** a dependency of this package. Install it separately if you want searchable memory:

```bash
dsh plugin add @kenz1117/dsh-engram
```

| Installed? | What you get |
|---|---|
| Yes | L1 + L2 + L3: proposals, approval, searchable propositions, and per-category knowledge pages. |
| No | L1 + L3. Ingest, review, approval, L1 storage, and knowledge pages all still work; proposals simply have nowhere to write their L2 section, so the retrieval layer degrades away. |

If the tool list of a running session shows no `engram_*` tools, the session was started before the plugin was installed — restart the Desktop app or open a new session. The skill explicitly forbids faking engram writes with files.

## Troubleshooting

**The skill does not appear, or you see a different `kb-curator`.**
This bundle registers its skill at the lowest precedence — bundled rank **600**. Any same-name skill found on disk outranks it:

| Source root | Rank |
|---|---|
| project `.dsh/skills` | 100 |
| project `.agents/skills` | 200 |
| custom roots | 300 |
| `~/.dsh/skills` | 400 |
| `~/.agents/skills` | 500 |

This is intentional: if you already maintain your own local `kb-curator` skill, yours wins and this package's entry is shadowed in the catalog rather than duplicated. Remove or rename the local copy if you want the bundled one.

**`AuthorizationManager check failed.`**
You called `kb.ps1` directly. Call `kb.cmd` instead, or pass `-ExecutionPolicy Bypass` to your own `powershell.exe` invocation. See [Platform support](#platform-support).

**`[警告] 缺少规范文件：…` (missing specification files).**
The engine directory was not copied in full. `init` only builds directories and page skeletons — it does not reconstruct the specification files. Re-copy the complete `engine/` directory, including `_system/` and `_templates/`, then run `kb.cmd status` to confirm the report says the specifications are complete.

**`[磁盘告警] …本次收料继续，但请立即提醒用户清理磁盘`.**
Free space on the knowledge base drive has fallen below `storage.warn_free_gb` (default 20 GB). The ingest still completes. Clean up, starting with `_staging/`. If the message says the ingest was **refused**, free space is below `storage.block_free_gb` (default 5 GB), the command exited 1, and nothing was written — free space first; do not redirect the write to another drive to get around it.

**`list-queue` is empty.**
Expected. `add` ingests and registers; it never writes a proposal. Proposals are written by the agent after reading the ingested copy.

**`approve` reports a missing `inbox_path`.**
The proposal is missing a required frontmatter field. Frontmatter is what `approve` reads — fields placed in the body are ignored, and the script degrades silently rather than erroring. Fill in the fields defined by `_templates/review-proposal.md`; `list-queue` is where the warnings show up.

**The L1 library has two cards for one document (`…-2.md`).**
Someone wrote L1 before approving. L1 is always written by `approve`; a name collision gets a `-2` suffix rather than an overwrite, which is how the duplicate appears. Keep the card written by `approve`.

**`kb.cmd` prints `'xxx' is not recognized as an internal or external command`.**
Non-ASCII text got into `kb.cmd`. Keep the file pure ASCII.

**Non-ASCII text is garbled.**
`kb.ps1` lost its UTF-8 BOM; re-save it as "UTF-8 with BOM".

## Self-check

The package ships its own asset contract check, runnable in a fresh clone with **no install step** — it uses only `node:` builtins:

```bash
node scripts/check-assets.mjs
```

It verifies:

1. **Skill metadata agreement** — `SKILL.md` frontmatter parses, and its `name` / `description` are byte-identical to `SKILL_NAME` / `SKILL_DESCRIPTION` in `lib/index.js`. Drift here is otherwise silent: the catalog would advertise one trigger while the body says something else.
2. **Asset completeness** — every reference document and every engine file exists and is non-empty.
3. **No machine-specific paths** — no shipped asset contains a path that only resolves on the author's machine.
4. **Encoding rules** — `kb.ps1` carries a UTF-8 BOM, `kb.cmd` is pure ASCII, and no other shipped asset carries a BOM.
5. **Engine scaffold coherence** — `kb.config.json` parses, its categories are non-empty, its warn threshold sits above its block threshold, `_system/log.jsonl` ships empty, and `cordis.patch.yml` mounts the package name declared in `package.json`.

`npm test` and `npm run check` are wired to the same script.

There is no CI workflow in this repository yet — run the self-check locally before committing. Adding `.github/workflows/` requires a token with the `workflow` scope, which is why this check is not automated here.

## License

MIT — Copyright (c) 2026 Mark-mph. See [`LICENSE`](LICENSE).

## Links

- Repository: <https://github.com/Mark-mph/dsh-kb-curator>
- Issues: <https://github.com/Mark-mph/dsh-kb-curator/issues>
- Engine manual: [`assets/kb-curator/engine/README.md`](assets/kb-curator/engine/README.md)
- Skill body: [`assets/kb-curator/SKILL.md`](assets/kb-curator/SKILL.md)
