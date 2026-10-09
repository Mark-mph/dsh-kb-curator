#requires -Version 5.1
<#
.SYNOPSIS
  智能知识储备体系 辅助脚本 kb.ps1（冻结契约 v1 §7）

.DESCRIPTION
  纯 PowerShell、无外部依赖、幂等；错误信息为中文。
  铁律：本脚本不含任何 Remove-Item；library/ 只新增文件、绝不覆盖；
        用户原始文件只读不写（add 只做副本）；**kb.ps1 永不写 engram**。
  Lead 集成裁定（2026-10）：
    - add  只把资料收进 _inbox/ 并生成初始元数据（*.meta.md），**不生成提案**；
           提案由 agent 读完资料后按 _templates/review-proposal.md 写入 _review/queue/。
    - approve 只做文件层动作 ① L1 落盘 ② 提案移入 _review/approved/ ③ 追加日志
           ④ stdout 打印醒目下一步指令（提示 agent 去 engram_save 与更新 pages/）。
           默认不动 pages/（需要机械追加一行索引时加 -UpdatePage）。
  命令（契约 §7）：
    init                                   创建/补齐目录树与骨架（幂等）
    add    -Path <文件> [-Category <c>]     资料收进 _inbox/ + 生成初始元数据
    list-queue                             列出 _review/queue/ 待审提案
    show   <id>                            查看提案 / 归档提案 / L1 原文卡
    approve <id>                           用户批准 → L1 落盘 + 提案归档 + 日志 + 下一步指令
    reject <id> -Reason "..."              用户驳回 → 归档理由，材料移入 _inbox/_rejected/
    search <query>                         在 library/、pages/、待审队列里做字面检索
    page   <大类>                           查看知识页（不带参数则列出全部）
    log    [-Tail N]                       查看操作日志 _system/log.jsonl

.EXAMPLE
  kb.cmd init
  kb.cmd add -Path "D:\notes\vite.md" -Category 技术工程
  kb.cmd list-queue
  kb.cmd approve kb-20261009-0001
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)][string]$Command = 'help',
    [Parameter(Position = 1)][string]$Target = '',
    [string]$Path = '',
    [string]$Category = '',
    [string]$Subcategory = '',
    [string]$Title = '',
    [string]$SourceType = '',
    [string]$Url = '',
    [int]$Priority = 3,
    [double]$Confidence = 0.8,
    [string[]]$Tags = @(),
    [string]$PropositionKey = '',
    [string]$Reason = '',
    [int]$Tail = 20,
    [switch]$Create,
    [switch]$UpdatePage,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }

$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$script:KbRoot = $PSScriptRoot
if ([string]::IsNullOrEmpty($script:KbRoot)) { $script:KbRoot = Split-Path -Parent $MyInvocation.MyCommand.Path }

# ============================================================
# 基础工具
# ============================================================

function Write-Ok([string]$m) { Write-Host $m -ForegroundColor Green }
function Write-Info([string]$m) { Write-Host $m }
function Write-Warn2([string]$m) { Write-Host $m -ForegroundColor Yellow }
function Fail([string]$m) { Write-Host ('[错误] ' + $m) -ForegroundColor Red; exit 1 }

function Read-Text([string]$p) { return [System.IO.File]::ReadAllText($p, $script:Utf8NoBom) }

function Write-Text([string]$p, [string]$t) {
    $d = Split-Path -Parent $p
    if ($d -and -not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    [System.IO.File]::WriteAllText($p, $t, $script:Utf8NoBom)
}

function Append-Text([string]$p, [string]$t) {
    $d = Split-Path -Parent $p
    if ($d -and -not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    [System.IO.File]::AppendAllText($p, $t, $script:Utf8NoBom)
}

function Ensure-Dir([string]$p) {
    if (-not (Test-Path -LiteralPath $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null; return $true }
    return $false
}

# ------------------------------------------------------------
# 磁盘空间守卫（用户硬要求：知识库所在盘快存满时，必须提前告诉用户）
# 返回知识库根目录所在盘的剩余空间（GB，一位小数）；读不到返回 -1。
# ------------------------------------------------------------
function Get-KbDriveFreeGB {
    $root = $script:KbRoot
    if ([string]::IsNullOrEmpty($root)) { $root = (Get-Location).Path }
    if ($root -notmatch '^([A-Za-z]):') { return -1 }
    $letter = $Matches[1]
    try {
        $drv = Get-PSDrive -Name $letter -PSProvider FileSystem -ErrorAction Stop
        if ($null -eq $drv.Free) { return -1 }
        return [math]::Round(($drv.Free / 1GB), 1)
    } catch { return -1 }
}

# 阈值来自 kb.config.json 的 storage.warn_free_gb / storage.block_free_gb（缺省 20 / 5）
function Get-StorageGuard {
    $warn = 20.0
    $block = 5.0
    $cfg = $script:Cfg
    if ($null -ne $cfg) {
        $names = @($cfg.PSObject.Properties | ForEach-Object { $_.Name })
        if ($names -contains 'storage' -and $null -ne $cfg.storage) {
            $sn = @($cfg.storage.PSObject.Properties | ForEach-Object { $_.Name })
            if ($sn -contains 'warn_free_gb' -and $null -ne $cfg.storage.warn_free_gb) { $warn = [double]$cfg.storage.warn_free_gb }
            if ($sn -contains 'block_free_gb' -and $null -ne $cfg.storage.block_free_gb) { $block = [double]$cfg.storage.block_free_gb }
        }
    }
    return [pscustomobject]@{ Warn = $warn; Block = $block; Free = (Get-KbDriveFreeGB) }
}

# 收料前的空间闸门：低于 block 直接拒绝（exit 1），低于 warn 放行但醒目标红提示
function Assert-DiskSpaceForIngest {
    $g = Get-StorageGuard
    if ($g.Free -lt 0) { return }
    if ($g.Free -lt $g.Block) {
        Fail ('知识库所在磁盘剩余空间不足（仅 ' + $g.Free + ' GB，安全线 ' + $g.Block + ' GB）。为避免写入失败或资料损坏，已拒绝本次收料。请清理磁盘后重试，并务必提醒用户。')
    }
    if ($g.Free -lt $g.Warn) {
        Write-Warn2 ('[磁盘告警] 知识库所在磁盘仅剩 ' + $g.Free + ' GB（预警线 ' + $g.Warn + ' GB）。本次收料继续，但请立即提醒用户清理磁盘。')
    }
}

# 读取任意编码的文本资料：UTF-8(BOM/无BOM) 优先，失败退回系统 ANSI(中文=GBK)
function Read-AnyText([string]$file) {
    $bytes = [System.IO.File]::ReadAllBytes($file)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        return [System.Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3)
    }
    try {
        $strict = New-Object System.Text.UTF8Encoding($false, $true)
        return $strict.GetString($bytes)
    } catch {
        return [System.Text.Encoding]::Default.GetString($bytes)
    }
}

function Get-Cfg {
    $p = Join-Path $script:KbRoot 'kb.config.json'
    if (Test-Path -LiteralPath $p) {
        try { return (ConvertFrom-Json (Read-Text $p)) } catch { }
    }
    return [pscustomobject]@{
        name                = '智能知识储备体系'
        version             = '1.0.0'
        default_category    = '未分类'
        default_subcategory = '通用'
        categories          = @('技术工程', '产品业务', '学术研究', '生活健康', '财务投资', '人文社科', '工具流程', '未分类')
        l2_scope_default    = 'user'
    }
}

function Get-Sha256Text([string]$s) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $h = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($s))
        return (($h | ForEach-Object { $_.ToString('x2') }) -join '')
    } finally { $sha.Dispose() }
}

function ConvertTo-Slug([string]$s) {
    if ([string]::IsNullOrWhiteSpace($s)) { return 'note' }
    $t = $s.Trim().ToLowerInvariant()
    $t = $t -replace '\s+', '-'
    $t = $t -replace '[\\/:*?"<>|#%&{}$!''`~^,.;\[\]()@+=]', ''
    $t = $t -replace '-{2,}', '-'
    $t = $t.Trim('-')
    if ($t.Length -gt 40) { $t = $t.Substring(0, 40).Trim('-') }
    if ([string]::IsNullOrWhiteSpace($t)) { $t = 'note' }
    return $t
}

function YamlStr([string]$v) {
    if ($null -eq $v) { $v = '' }
    return '"' + ($v -replace '"', '\"') + '"'
}

function Pick($h, [string]$k, [string]$d) {
    if ($h -and $h.ContainsKey($k)) {
        $v = [string]$h[$k]
        if (-not [string]::IsNullOrWhiteSpace($v)) { return $v.Trim() }
    }
    return $d
}

function Get-Frontmatter([string]$text) {
    $fm = @{}
    $lines = $text -split "`r?`n"
    if ($lines.Count -lt 2 -or $lines[0].Trim() -ne '---') { return $fm }
    for ($i = 1; $i -lt $lines.Count; $i++) {
        $ln = $lines[$i]
        if ($ln.Trim() -eq '---') { break }
        if ($ln -match '^\s*#') { continue }
        if ($ln -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*:\s*(.*)$') {
            $k = $matches[1]
            $v = $matches[2].Trim()
            if ($v.Length -ge 2 -and (($v.StartsWith('"') -and $v.EndsWith('"')) -or ($v.StartsWith("'") -and $v.EndsWith("'")))) {
                $v = $v.Substring(1, $v.Length - 2)
            }
            $fm[$k] = $v
        }
    }
    return $fm
}

function Write-KbLog([string]$Action, [string]$TargetName, [string]$Note, [hashtable]$Extra) {
    $logPath = Join-Path $script:KbRoot '_system\log.jsonl'
    Ensure-Dir (Split-Path -Parent $logPath) | Out-Null
    $entry = [ordered]@{
        ts     = (Get-Date).ToString('yyyy-MM-ddTHH:mm:sszzz')
        actor  = 'kb.ps1'
        action = $Action
        target = $TargetName
        note   = $Note
    }
    if ($Extra) {
        foreach ($k in $Extra.Keys) { $entry[$k] = $Extra[$k] }
    }
    Append-Text $logPath ((ConvertTo-Json $entry -Compress) + "`n")
}

function Get-Taxonomy {
    $p = Join-Path $script:KbRoot '_system\taxonomy.yml'
    $list = New-Object System.Collections.ArrayList
    if (-not (Test-Path -LiteralPath $p)) { return $list }
    $cur = $null
    foreach ($ln in ((Read-Text $p) -split "`r?`n")) {
        if ($ln -match '^\s*-\s*name:\s*(.+?)\s*$') {
            $nm = $matches[1].Trim().Trim('"').Trim("'")
            $cur = [pscustomobject]@{ name = $nm; keywords = @() }
            [void]$list.Add($cur)
        } elseif ($cur -and $ln -match '^\s*keywords:\s*\[(.*)\]\s*$') {
            $kw = @()
            foreach ($k in ($matches[1] -split ',')) { $t = $k.Trim(); if ($t) { $kw += $t } }
            $cur.keywords = $kw
        }
    }
    return $list
}

function Get-SuggestedCategory([string]$text, [string]$defaultCat) {
    $tax = Get-Taxonomy
    $best = ''
    $bestScore = 0
    $bestHits = @()
    foreach ($c in $tax) {
        $hits = @()
        foreach ($k in $c.keywords) {
            if ($k -and ($text.IndexOf($k, [System.StringComparison]::OrdinalIgnoreCase) -ge 0)) { $hits += $k }
        }
        if ($hits.Count -gt $bestScore) { $bestScore = $hits.Count; $best = $c.name; $bestHits = $hits }
    }
    if (-not $best) { return @{ category = $defaultCat; hits = @() } }
    return @{ category = $best; hits = $bestHits }
}

function Get-CategoryHits([string]$catName, [string]$text) {
    # 某一大类自身关键词在文本里的命中（用于「调用方显式指定 -Category」时给参考依据）
    if ([string]::IsNullOrWhiteSpace($catName)) { return @() }
    $hits = @()
    foreach ($c in (Get-Taxonomy)) {
        if ($c.name -ne $catName) { continue }
        foreach ($k in $c.keywords) {
            if ($k -and ($text.IndexOf($k, [System.StringComparison]::OrdinalIgnoreCase) -ge 0)) { $hits += $k }
        }
    }
    return $hits
}

function Get-NextKbId {
    $stamp = (Get-Date).ToString('yyyyMMdd')
    $max = 0
    $roots = @('_review\queue', '_review\approved', '_review\rejected', '_inbox', 'library')
    foreach ($r in $roots) {
        $d = Join-Path $script:KbRoot $r
        if (-not (Test-Path -LiteralPath $d)) { continue }
        foreach ($f in (Get-ChildItem -LiteralPath $d -Recurse -File -ErrorAction SilentlyContinue)) {
            if ($f.Name -match '^kb-(\d{8})-(\d{4})') {
                if ($matches[1] -eq $stamp) {
                    $n = [int]$matches[2]
                    if ($n -gt $max) { $max = $n }
                }
            }
        }
    }
    return ('kb-{0}-{1:0000}' -f $stamp, ($max + 1))
}

function Get-PagePath([string]$cat) { return (Join-Path $script:KbRoot (Join-Path 'pages' ($cat + '.md'))) }

function New-PageSkeleton([string]$cat) {
    $tpl = Join-Path $script:KbRoot '_templates\knowledge-page.md'
    $content = ''
    if (Test-Path -LiteralPath $tpl) {
        $content = ((Read-Text $tpl) -replace '\{\{CATEGORY\}\}', $cat)
    } else {
        $content = "---`ncategory: `"$cat`"`nupdated_at: `"`"`nentry_count: 0`n---`n`n# $cat · 知识页`n`n## 已入库条目索引`n`n<!-- KB:INDEX:BEGIN -->`n<!-- KB:INDEX:END -->`n"
    }
    Write-Text (Get-PagePath $cat) $content
}

function Add-PageIndexLine([string]$cat, [string]$line) {
    $p = Get-PagePath $cat
    if (-not (Test-Path -LiteralPath $p)) { New-PageSkeleton $cat }
    $text = Read-Text $p
    if ($text -notmatch 'KB:INDEX:END') {
        $text = $text.TrimEnd() + "`n`n## 已入库条目索引`n`n<!-- KB:INDEX:BEGIN -->`n<!-- KB:INDEX:END -->`n"
    }
    $safe = $line.Replace('$', '$$')
    $text = [regex]::Replace($text, '(?m)^<!-- KB:INDEX:END -->', ($safe + "`n<!-- KB:INDEX:END -->"))
    if ($text -match '(?m)^entry_count:\s*(\d+)') {
        $newCount = [int]$matches[1] + 1
        $text = [regex]::Replace($text, '(?m)^entry_count:\s*\d+', ('entry_count: ' + $newCount))
    }
    if ($text -match '(?m)^updated_at:') {
        $text = [regex]::Replace($text, '(?m)^updated_at:.*$', ('updated_at: "' + (Get-Date).ToString('yyyy-MM-ddTHH:mm:sszzz') + '"'))
    }
    Write-Text $p $text
}

function Get-OneLineSummary([string]$raw) {
    $buf = New-Object System.Collections.ArrayList
    foreach ($ln in ($raw -split "`r?`n")) {
        $l = $ln.Trim()
        if ($l -eq '') { continue }
        if ($l -match '^#{1,6}\s') { continue }        # 跳过标题行
        if ($l -match '^```') { continue }              # 跳过代码围栏
        if ($l -match '^[-*+]\s') { $l = $l.Substring(1).Trim() }
        [void]$buf.Add($l)
        if (($buf -join ' ').Length -ge 60) { break }
    }
    # 多行之间用 ' · ' 连接，否则「…是 5173」+「前端构建工具…」会粘成「…是 5173 前端构建工具…」
    $one = (($buf | Select-Object -First 3) -join ' · ')
    $one = ($one -replace '\s+', ' ').Trim()
    if ([string]::IsNullOrWhiteSpace($one)) { $one = ($raw.Trim() -replace '\s+', ' ') }
    if ($one.Length -gt 80) { $one = $one.Substring(0, 80) + '…' }
    return $one
}

function Cmd-Status {
    $cfg = $script:Cfg
    $g = Get-StorageGuard
    Write-Info ''
    Write-Ok ('[知识库] ' + $script:KbRoot)
    if ($g.Free -ge 0) {
        Write-Info ('         所在磁盘剩余空间：' + $g.Free + ' GB（预警线 ' + $g.Warn + ' GB / 拒绝线 ' + $g.Block + ' GB）')
        if ($g.Free -lt $g.Block) {
            Write-Warn2 '         [磁盘告警] 剩余空间已低于拒绝线：kb.cmd add 会被拒绝，请立即清理磁盘并告知用户。'
        } elseif ($g.Free -lt $g.Warn) {
            Write-Warn2 '         [磁盘告警] 剩余空间已低于预警线，请提醒用户清理磁盘。'
        }
    } else {
        Write-Info '         所在磁盘剩余空间：无法读取（跳过空间检查）'
    }
    $libCount = @(Get-ChildItem -LiteralPath (Join-Path $script:KbRoot 'library') -Recurse -File -ErrorAction SilentlyContinue).Count
    $queueCount = @(Get-QueueFiles).Count
    $approvedCount = @(Get-ChildItem -LiteralPath (Join-Path $script:KbRoot '_review\approved') -File -ErrorAction SilentlyContinue).Count
    $rejectedCount = @(Get-ChildItem -LiteralPath (Join-Path $script:KbRoot '_review\rejected') -File -ErrorAction SilentlyContinue).Count
    $inboxCount = @(Get-ChildItem -LiteralPath (Join-Path $script:KbRoot '_inbox') -File -ErrorAction SilentlyContinue).Count
    $pageCount = @(Get-ChildItem -LiteralPath (Join-Path $script:KbRoot 'pages') -File -ErrorAction SilentlyContinue).Count
    $logLines = 0
    $lp = Join-Path $script:KbRoot '_system\log.jsonl'
    if (Test-Path -LiteralPath $lp) { $logLines = @(Get-Content -LiteralPath $lp -ErrorAction SilentlyContinue).Count }
    $logBytes = 0
    if (Test-Path -LiteralPath $lp) { $logBytes = (Get-Item -LiteralPath $lp).Length }
    Write-Info ('         待审提案 ' + $queueCount + ' · 已批准提案 ' + $approvedCount + ' · 已驳回 ' + $rejectedCount)
    Write-Info ('         L0 暂存 ' + $inboxCount + ' 文件 · L1 原文 ' + $libCount + ' 篇 · L3 知识页 ' + $pageCount + ' 张 · 日志 ' + $logLines + ' 行/' + $logBytes + ' 字节')
    $missing = @()
    $required = @('kb.config.json', 'README.md', '_system\taxonomy.yml', '_system\priority.yml', '_system\arbitration.md', '_system\entry-schema.md', '_system\review-workflow.md', '_system\learning.md', '_system\log.jsonl', '_templates\source-note.md', '_templates\memory-entry.md', '_templates\knowledge-page.md', '_templates\review-proposal.md')
    foreach ($r in $required) { if (-not (Test-Path -LiteralPath (Join-Path $script:KbRoot $r))) { $missing += $r } }
    if ($missing.Count -gt 0) { Write-Warn2 ('         [警告] 缺少规范文件：' + ($missing -join '、')) } else { Write-Info '         规范文件齐备' }
    Write-Info ''
}

function Show-Help {
    Write-Info ''
    Write-Info '智能知识储备体系 kb.ps1 —— 三层：L1 原文库 / L2 engram 记忆 / L3 知识页'
    Write-Info '铁律：用户批准前不写 L1/L2/L3；kb.ps1 永不写 engram；不删除任何已有资料。'
    Write-Info ''
    Write-Info '用法：'
    Write-Info '  kb.cmd init                              创建/补齐目录树（幂等）'
    Write-Info '  kb.cmd status                            查看知识库状态、条目计数与所在磁盘剩余空间'
    Write-Info '  kb.cmd add -Path <文件> [-Category <大类>]  资料收进 _inbox/ 并生成初始元数据'
    Write-Info '  kb.cmd list-queue                        列出待审提案（_review/queue/）'
    Write-Info '  kb.cmd show <id>                         查看提案 / 归档 / L1 原文卡'
    Write-Info '  kb.cmd approve <id> [-UpdatePage]        批准 → L1 落盘 + 提案归档 + 打印下一步'
    Write-Info '  kb.cmd reject <id> -Reason "..."         驳回并归档理由'
    Write-Info '  kb.cmd search <关键词>                    在 library/pages/待审队列做字面检索'
    Write-Info '  kb.cmd page <大类> [-Create]              查看知识页（不带参数列出全部）'
    Write-Info '  kb.cmd log [-Tail 20]                    查看操作日志'
    Write-Info ''
    Write-Info '流程：add（收料）→ agent 读料写提案 → 用户批阅 → approve（落盘）→ agent 写 L2 + 更新 L3'
    Write-Info ''
}

# ============================================================
# 命令实现
# ============================================================

function Cmd-Init {
    $cfg = $script:Cfg
    $created = @()
    $skipped = @()
    $dirs = @('_inbox', '_inbox\_rejected', '_review', '_review\queue', '_review\approved', '_review\rejected', '_system', '_templates', 'library', 'pages')
    foreach ($c in $cfg.categories) { $dirs += (Join-Path 'library' $c) }
    foreach ($d in $dirs) {
        $abs = Join-Path $script:KbRoot $d
        if (Ensure-Dir $abs) { $created += $d } else { $skipped += $d }
    }
    $logPath = Join-Path $script:KbRoot '_system\log.jsonl'
    if (-not (Test-Path -LiteralPath $logPath)) {
        # 只用「无 BOM 的 UTF-8」建空日志：带 BOM 时 Node JSON.parse / Python json.loads
        # 直接读第一行会因为 \uFEFF 前缀报错；不要用 Set-Content -Encoding UTF8（PS 5.1 会加 BOM）。
        [System.IO.File]::WriteAllText($logPath, '', (New-Object System.Text.UTF8Encoding($false)))
        $created += '_system\log.jsonl'
    } else {
        $skipped += '_system\log.jsonl'   # 已存在一律不动：幂等，绝不截断用户已有日志
    }
    foreach ($c in $cfg.categories) {
        $pp = Get-PagePath $c
        if (-not (Test-Path -LiteralPath $pp)) { New-PageSkeleton $c; $created += ('pages\' + $c + '.md') } else { $skipped += ('pages\' + $c + '.md') }
    }
    $required = @('kb.config.json', 'README.md', '_system\taxonomy.yml', '_system\priority.yml', '_system\arbitration.md', '_system\entry-schema.md', '_system\review-workflow.md', '_system\learning.md', '_system\log.jsonl', '_templates\source-note.md', '_templates\memory-entry.md', '_templates\knowledge-page.md', '_templates\review-proposal.md')
    $missing = @()
    foreach ($r in $required) { if (-not (Test-Path -LiteralPath (Join-Path $script:KbRoot $r))) { $missing += $r } }

    Write-Ok ('[OK] 知识库根目录：' + $script:KbRoot)
    $freeGb = Get-KbDriveFreeGB
    if ($freeGb -ge 0) {
        $suffix = ''
        if ($freeGb -lt 20) { $suffix = '   ← 已低于 20 GB 预警线，请提醒用户清理磁盘' }
        Write-Info ('     所在磁盘剩余空间：' + $freeGb + ' GB' + $suffix)
    }
    Write-Info ('     新建 ' + $created.Count + ' 项，已存在跳过 ' + $skipped.Count + ' 项（init 幂等，不覆盖任何文件）')
    if ($missing.Count -gt 0) {
        Write-Warn2 ('[警告] 缺少以下规范文件，请从 _templates/ 或备份恢复：' + ($missing -join '、'))
    } else {
        Write-Info '     规范文件齐备：taxonomy / priority / arbitration / entry-schema / review-workflow / 4 个模板'
    }
    Write-Info ('     大类 ' + $cfg.categories.Count + ' 个：' + ($cfg.categories -join '、'))
    Write-Info ''
    Write-Info '下一步：kb.cmd add -Path <你的资料文件>  →  agent 据初始元数据写提案  →  kb.cmd list-queue'
    Write-KbLog 'init' $script:KbRoot ('created=' + $created.Count + ';skipped=' + $skipped.Count + ';missing=' + $missing.Count) @{ by = 'agent'; l2_pending = $false }
}

function Cmd-Add {
    $cfg = $script:Cfg
    if ([string]::IsNullOrWhiteSpace($Path)) { Fail 'add 需要 -Path 指定资料文件。例：kb.cmd add -Path "D:\notes\vite.md" -Category 技术工程' }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { Fail ('找不到文件：' + $Path) }
    $full = (Resolve-Path -LiteralPath $Path).Path
    $raw = Read-AnyText $full
    if ([string]::IsNullOrEmpty($raw)) { Fail ('文件内容为空，未摄入：' + $full) }
    if ($raw.IndexOf([char]0) -ge 0) { Fail '该文件像是二进制文件。知识库只收文本资料（Markdown/TXT），请先转成 Markdown。' }
    Assert-DiskSpaceForIngest   # 用户硬要求：磁盘快满时必须提前告警/拒绝，不能闷头写

    # 标题：-Title > 正文首个一级标题 > 文件名
    $title = $Title
    if ([string]::IsNullOrWhiteSpace($title)) {
        foreach ($ln in ($raw -split "`r?`n")) {
            if ($ln -match '^\s*#\s+(.+?)\s*$') { $title = $matches[1].Trim(); break }
        }
    }
    if ([string]::IsNullOrWhiteSpace($title)) { $title = [System.IO.Path]::GetFileNameWithoutExtension($full) }

    # 来源类型与来源等级（契约 §1 / priority.yml）
    $st = $SourceType
    if ([string]::IsNullOrWhiteSpace($st)) { if ($Url) { $st = 'web' } else { $st = 'user_file' } }
    if (@('user_file', 'user_text', 'web') -notcontains $st) { Fail ('source_type 只能是 user_file / user_text / web，收到：' + $st) }
    if ($st -eq 'web' -and [string]::IsNullOrWhiteSpace($Url)) { Fail 'source_type=web 时必须提供 -Url（提案里还要记录 fetched_at）。' }
    $rank = 100
    if ($st -eq 'web') { $rank = 20 }   # 未审核的联网结果一律 20；用户批准后 L1 status=approved → 60

    # 分类：显式 -Category 优先；否则按 taxonomy 关键词自动打分
    $scan = $title + "`n" + $raw
    if ($scan.Length -gt 4000) { $scan = $scan.Substring(0, 4000) }
    $catExplicit = -not [string]::IsNullOrWhiteSpace($Category)
    $hits = @()
    if ($catExplicit) {
        $cat = $Category
        $hits = Get-CategoryHits $cat $scan     # 指定也照算一次，作为审核参考信息
    } else {
        $sug = Get-SuggestedCategory $scan $cfg.default_category
        $cat = $sug.category
        $hits = $sug.hits
    }
    if ($cfg.categories -notcontains $cat) { Fail ('未知大类「' + $cat + '」。可选：' + ($cfg.categories -join '、') + '（可改 kb.config.json 或 _system/taxonomy.yml 扩展）') }
    $sub = $Subcategory
    if ([string]::IsNullOrWhiteSpace($sub)) { $sub = $cfg.default_subcategory }

    # 去重：与已有 L1 / L0 副本比对 content_hash
    $hash = Get-Sha256Text $raw
    $dup = ''
    foreach ($r in @('library', '_inbox')) {
        $d = Join-Path $script:KbRoot $r
        if (-not (Test-Path -LiteralPath $d)) { continue }
        foreach ($f in (Get-ChildItem -LiteralPath $d -Recurse -File -Filter '*.md' -ErrorAction SilentlyContinue)) {
            if ($f.Name -like '*.meta.md') { continue }
            if ((Get-Sha256Text (Read-AnyText $f.FullName)) -eq $hash) { $dup = $f.FullName; break }
        }
        if ($dup) { break }
    }
    if ($dup -and -not $Force) {
        Write-Warn2 ('[疑似重复] 相同内容的资料已存在：' + $dup.Substring($script:KbRoot.Length + 1))
        Fail '为避免重复条目，本次未摄入。确认要再收一份时加 -Force。'
    }

    $id = Get-NextKbId
    $slug = ConvertTo-Slug $title
    $addedAt = (Get-Date).ToString('yyyy-MM-ddTHH:mm:sszzz')
    $propKey = $PropositionKey
    if ([string]::IsNullOrWhiteSpace($propKey)) { $propKey = $cat + '/' + $sub + '/' + $slug }
    $confStr = $Confidence.ToString('0.0#', [System.Globalization.CultureInfo]::InvariantCulture)
    $tagsInline = '[' + ($Tags -join ', ') + ']'
    $oneLine = Get-OneLineSummary $raw
    $excerpt = $raw.Trim()
    if ($excerpt.Length -gt 300) { $excerpt = $excerpt.Substring(0, 300) + '…' }
    $l2content = $title + '：（待 agent 从原文提炼结论）。条件：（待确认）。来源：' + $id + '。 [src:' + $id + ']'
    if ($catExplicit) {
        if ($hits.Count -gt 0) { $catBasis = '调用方显式指定 -Category；该大类关键词命中：' + ($hits -join '、') }
        else { $catBasis = '调用方显式指定 -Category（未命中该大类关键词，仅作参考）' }
    } elseif ($hits.Count -gt 0) {
        $catBasis = '自动分类：命中关键词：' + ($hits -join '、')
    } else {
        $catBasis = '自动分类：未命中 taxonomy 关键词，归入默认大类'
    }

    # ① L0 副本（用户原文件只读，不动）
    $inboxRel = '_inbox/' + $id + '-' + $slug + '.md'
    $inboxAbs = Join-Path $script:KbRoot ($inboxRel -replace '/', '\')
    Ensure-Dir (Split-Path -Parent $inboxAbs) | Out-Null
    Write-Text $inboxAbs $raw

    # ② 初始元数据（供 agent 据此写提案；kb.ps1 自己**不**生成提案）
    $metaRel = '_inbox/' + $id + '-' + $slug + '.meta.md'
    $metaParent = Join-Path $script:KbRoot ('_inbox\' + $id + '-' + $slug + '.meta.md')
    $meta = @()
    $meta += '---'
    $meta += '# 初始元数据：kb.cmd add 生成的建议值，agent 可修改；据此写 _review/queue/' + $id + '.md'
    $meta += 'id: ' + $id
    $meta += 'title: ' + (YamlStr $title)
    $meta += 'category_suggested: ' + $cat
    $meta += 'category_basis: ' + (YamlStr $catBasis)
    $meta += 'subcategory_suggested: ' + $sub
    $meta += 'source_type: ' + $st
    $meta += 'source_url: ' + (YamlStr $Url)
    $meta += 'source_rank: ' + $rank
    $meta += 'content_hash: ' + (YamlStr $hash)
    $meta += 'added_at: ' + $addedAt
    $meta += 'priority_suggested: ' + $Priority
    $meta += 'confidence_suggested: ' + $confStr
    $meta += 'proposition_key: ' + (YamlStr $propKey)
    $meta += 'tags: ' + $tagsInline
    $meta += 'l2_kind: fact'
    $meta += 'l2_scope: ' + $cfg.l2_scope_default
    $meta += 'l2_content_suggestion: ' + (YamlStr $l2content)
    $meta += 'inbox_path: ' + (YamlStr $inboxRel)
    $meta += 'origin_path: ' + (YamlStr $full)
    $meta += 'status: inbox'
    $meta += '---'
    $meta += ''
    $meta += '# ' + $id + ' 初始元数据'
    $meta += ''
    $meta += '- 原文副本：`' + $inboxRel + '`（逐字保留；用户原文件 `' + $full + '` 未被改动）'
    $meta += '- 原文摘要：' + $excerpt
    $meta += ''
    $meta += '## agent 下一步（**kb.ps1 不会自动生成提案**）'
    $meta += ''
    $meta += '1. 读 `' + $inboxRel + '`，提炼结论与适用条件；'
    $meta += '2. 按 `_templates/review-proposal.md` 写 `_review/queue/' + $id + '.md`（`status: proposed`），'
    $meta += '   必填：id / title / category / subcategory / source_type / added_at / content_hash / status / priority / confidence / proposition_key / inbox_path / l2_kind / l2_scope / l2_content；'
    $meta += '3. 告诉用户「待审提案 ' + $id + ' 已就绪」，等用户批准（**批准前不得写 library/、engram、pages/**）。'
    $meta += ''
    Write-Text $metaParent (($meta -join "`n") + "`n")

    Write-Ok ('[OK] 已收料 ' + $id + '（仅 _inbox/，未落 L1、未写 engram、未更新知识页）')
    Write-Info ('     L0 原文副本：' + $inboxRel + '（用户原文件未改动）')
    Write-Info ('     初始元数据：_inbox\' + $id + '-' + $slug + '.meta.md')
    if ($catExplicit) { Write-Info ('     指定分类：' + $cat + '/' + $sub + '  依据：' + $catBasis) }
    else { Write-Info ('     建议分类：' + $cat + '/' + $sub + '  依据：' + $catBasis) }
    Write-Info ('     来源等级：' + $rank + '（' + $st + '）  priority=' + $Priority + '  confidence=' + $confStr)
    Write-Info ('     内容指纹：' + $hash)
    Write-Info ''
    Write-Warn2 ('[给 agent] 下一步：读 ' + $inboxRel + ' → 写 _review/queue/' + $id + '.md（按 _templates/review-proposal.md）→ 请用户批阅')
    Write-Info ('     用户侧：kb.cmd list-queue 查看；kb.cmd approve ' + $id + ' 入库 / kb.cmd reject ' + $id + ' -Reason "原因"')
    Write-KbLog 'add' $id ('file=' + $full + ';category=' + $cat + ';sub=' + $sub + ';rank=' + $rank + ';inbox=' + $inboxRel + ';meta=' + $metaRel) @{ by = 'agent'; l2_pending = $false }
}

function Get-QueueFiles {
    $q = Join-Path $script:KbRoot '_review\queue'
    if (-not (Test-Path -LiteralPath $q)) { return @() }
    return @(Get-ChildItem -LiteralPath $q -File -Filter '*.md' -ErrorAction SilentlyContinue | Sort-Object Name)
}

function Cmd-ListQueue {
    $files = Get-QueueFiles
    if ($files.Count -eq 0) {
        Write-Info '待审队列为空。'
        Write-Info 'kb.ps1 不再自动生成提案：先 kb.cmd add -Path <资料文件> 收料，再由 agent 按 _inbox/<id>.*.meta.md 写 _review/queue/<id>.md。'
        Write-KbLog 'list-queue' 'queue' 'empty' @{ by = 'agent'; l2_pending = $false }
        return
    }
    Write-Ok ('待审队列（' + $files.Count + ' 条，均未写入 L1/L2/L3）')
    Write-Info ''
    Write-Info ('{0,-22} {1,-10} {2,-6} {3,-8} {4,-6} {5}' -f 'id', '大类', '优先级', '置信度', '等级', '标题')
    Write-Info ('-' * 100)
    $incomplete = @()
    foreach ($f in $files) {
        $fm = Get-Frontmatter (Read-Text $f.FullName)
        $id = Pick $fm 'id' ([System.IO.Path]::GetFileNameWithoutExtension($f.Name))
        $c = Pick $fm 'category' '未分类'
        $p = Pick $fm 'priority' '3'
        $cf = Pick $fm 'confidence' '0.8'
        $rk = Pick $fm 'source_rank' '?'
        $ti = Pick $fm 'title' '(无标题)'
        if ($ti.Length -gt 34) { $ti = $ti.Substring(0, 34) + '…' }
        Write-Info ('{0,-22} {1,-10} {2,-6} {3,-8} {4,-6} {5}' -f $id, $c, $p, $cf, $rk, $ti)
        if (-not $fm.ContainsKey('inbox_path') -or -not $fm.ContainsKey('category')) { $incomplete += $id }
    }
    Write-Info ''
    if ($incomplete.Count -gt 0) {
        Write-Warn2 ('[警告] 以下提案缺 category 或 inbox_path：approve 不会报错，但会降级——category 缺失时落进「未分类/通用」，l2_content 为空时 L2 无内容，请先补全再批准：' + ($incomplete -join '、'))
        Write-Warn2 ('        （对照：只有当 _inbox/ 下连该 id 的 L0 副本都找不到时，approve 才会 exit=1 失败）')
    }
    Write-Info '查看详情：kb.cmd show <id>'
    Write-Info '批准：kb.cmd approve <id>      驳回：kb.cmd reject <id> -Reason "原因"'
    Write-KbLog 'list-queue' 'queue' ('count=' + $files.Count) @{ by = 'agent'; l2_pending = $false }
}

function Find-KbFileById([string]$id) {
    $cands = @()
    foreach ($d in @('_review\queue', '_review\approved', '_review\rejected')) {
        $abs = Join-Path $script:KbRoot $d
        if (-not (Test-Path -LiteralPath $abs)) { continue }
        $cands += @(Get-ChildItem -LiteralPath $abs -File -Filter ($id + '*.md') -ErrorAction SilentlyContinue)
    }
    if ($cands.Count -eq 0) {
        $lib = Join-Path $script:KbRoot 'library'
        if (Test-Path -LiteralPath $lib) {
            foreach ($f in (Get-ChildItem -LiteralPath $lib -Recurse -File -Filter '*.md' -ErrorAction SilentlyContinue)) {
                $head = Read-Text $f.FullName
                if ($head.Length -gt 1200) { $head = $head.Substring(0, 1200) }
                if ($head -match ('(?m)^id:\s*' + [regex]::Escape($id) + '\s*$')) { $cands += $f; break }
            }
        }
    }
    if ($cands.Count -eq 0) { return $null }
    return $cands[0]
}

function Cmd-Show([string]$id) {
    if ([string]::IsNullOrWhiteSpace($id)) { Fail 'show 需要 id。例：kb.cmd show kb-20261009-0001（先用 kb.cmd list-queue 查看）' }
    $f = Find-KbFileById $id
    if ($null -eq $f) { Fail ('找不到 id=' + $id + ' 的提案或原文卡。用 kb.cmd list-queue 查看待审 id。') }
    $rel = $f.FullName.Substring($script:KbRoot.Length + 1)
    Write-Ok ('[文件] ' + $rel)
    Write-Info ('-' * 100)
    Write-Info (Read-Text $f.FullName)
    Write-Info ('-' * 100)
    $fm = Get-Frontmatter (Read-Text $f.FullName)
    $st = Pick $fm 'status' '?'
    Write-Info ('status = ' + $st)
    if ($st -eq 'proposed') { Write-Info ('批准：kb.cmd approve ' + $id + '    驳回：kb.cmd reject ' + $id + ' -Reason "原因"') }
    Write-KbLog 'show' $id $rel @{ by = 'agent'; l2_pending = $false }
}

function Cmd-Approve([string]$id) {
    $cfg = $script:Cfg
    if ([string]::IsNullOrWhiteSpace($id)) { Fail 'approve 需要提案 id。例：kb.cmd approve kb-20261009-0001' }
    $qdir = Join-Path $script:KbRoot '_review\queue'
    $src = Join-Path $qdir ($id + '.md')
    if (-not (Test-Path -LiteralPath $src)) { Fail ('待审队列里找不到提案 ' + $id + '。用 kb.cmd list-queue 查看。') }
    $doc = Read-Text $src
    $fm = Get-Frontmatter $doc
    $status = Pick $fm 'status' 'proposed'
    if ($status -ne 'proposed') { Fail ('提案 ' + $id + ' 当前 status=' + $status + '，只有 proposed 才能批准。') }

    $catRaw = Pick $fm 'category' ''
    $catExplicit = $fm.ContainsKey('category') -and -not [string]::IsNullOrWhiteSpace($catRaw)
    $cat = $catRaw
    if (-not $catExplicit) { $cat = $cfg.default_category }
    if ($cfg.categories -notcontains $cat) { Write-Warn2 ('[警告] 大类「' + $cat + '」不在 kb.config.json 中，落盘时按原值写入。') }
    $sub = Pick $fm 'subcategory' $cfg.default_subcategory
    $title = Pick $fm 'title' $id
    $hash = Pick $fm 'content_hash' ''
    $linked = Pick $fm 'l2_content' ''
    $kind = Pick $fm 'l2_kind' 'fact'
    $scope = Pick $fm 'l2_scope' $cfg.l2_scope_default

    # 兜底容错必须「可听见」：缺关键字段时不 Fail（保留容错），但必须显著告警，不许静默降级
    $degraded = @()
    if (-not $catExplicit) { $degraded += ('缺 category（frontmatter 未显式给出）') }
    if ([string]::IsNullOrWhiteSpace($linked)) { $degraded += ('缺 l2_content（frontmatter 为空）') }
    if ($degraded.Count -gt 0) {
        $cons = @()
        if (-not $catExplicit) { $cons += ('L1 会落进「' + $cat + '/' + $sub + '」，不是提案指定的大类') }
        if ([string]::IsNullOrWhiteSpace($linked)) { $cons += ('打印的 engram_save(content="") 为空，L2 不会有内容，需 agent 从 L1 正文补齐') }
        Write-Warn2 ('[警告] 提案 ' + $id + ' 关键字段缺失：' + ($degraded -join '、') + ' —— approve 不会报错（容错继续），但结果是降级：')
        Write-Warn2 ('        后果：' + ($cons -join '；'))
        Write-Warn2 ('        建议：补齐提案 frontmatter（category / l2_content）后重新 kb.cmd approve ' + $id + '；或让 agent 按下面的 A) 从 L1 正文补出 l2_content（含 [src:' + $id + ']）再 engram_save')
    }

    # ① L1 落盘：原文取 L0 副本（用户原文件永不动）
    $inboxRel = Pick $fm 'inbox_path' ''
    $inboxAbs = ''
    if ($inboxRel) { $inboxAbs = Join-Path $script:KbRoot ($inboxRel -replace '/', '\') }
    if (-not $inboxAbs -or -not (Test-Path -LiteralPath $inboxAbs)) {
        $inboxDir = Join-Path $script:KbRoot '_inbox'
        $alt = @(Get-ChildItem -LiteralPath $inboxDir -File -Filter ($id + '*') -ErrorAction SilentlyContinue | Where-Object { $_.Name -notlike '*.meta.md' } | Select-Object -First 1)
        if ($alt.Count -gt 0) { $inboxAbs = $alt[0].FullName } else { $inboxAbs = '' }
    }
    if (-not $inboxAbs) { Fail ('找不到提案 ' + $id + ' 的 L0 原文副本（inbox_path=' + $inboxRel + '）。请用 kb.cmd add 重新收料后再批准。') }
    $raw = Read-AnyText $inboxAbs
    if ([string]::IsNullOrWhiteSpace($hash)) { $hash = Get-Sha256Text $raw }

    $datePart = ($id -split '-')[1]
    $dateDisp = $datePart.Substring(0, 4) + '-' + $datePart.Substring(4, 2) + '-' + $datePart.Substring(6, 2)
    $slug = ConvertTo-Slug $title
    $libDir = Join-Path (Join-Path $script:KbRoot 'library') (Join-Path $cat $sub)
    Ensure-Dir $libDir | Out-Null
    $base = $dateDisp + '-' + $slug
    $dest = Join-Path $libDir ($base + '.md')
    $n = 2
    while (Test-Path -LiteralPath $dest) { $dest = Join-Path $libDir ($base + '-' + $n + '.md'); $n++ }   # 绝不覆盖已有资料
    $libRel = $dest.Substring($script:KbRoot.Length + 1)

    $now = (Get-Date).ToString('yyyy-MM-ddTHH:mm:sszzz')
    $l1 = @()
    $l1 += '---'
    $l1 += 'id: ' + $id
    $l1 += 'title: ' + (YamlStr $title)
    $l1 += 'category: ' + $cat
    $l1 += 'subcategory: ' + $sub
    $l1 += 'source_type: ' + (Pick $fm 'source_type' 'user_file')
    $l1 += 'source_url: ' + (YamlStr (Pick $fm 'source_url' ''))
    $l1 += 'fetched_at: ' + (YamlStr (Pick $fm 'fetched_at' ''))
    $l1 += 'added_at: ' + (Pick $fm 'added_at' $now)
    $l1 += 'content_hash: ' + (YamlStr $hash)
    $l1 += 'status: approved'
    $l1 += 'priority: ' + (Pick $fm 'priority' '3')
    $l1 += 'confidence: ' + (Pick $fm 'confidence' '0.8')
    $l1 += 'valid_from: ' + (YamlStr (Pick $fm 'valid_from' ''))
    $l1 += 'valid_until: ' + (YamlStr (Pick $fm 'valid_until' ''))
    $l1 += 'supersedes: ' + (Pick $fm 'supersedes' '[]')
    $l1 += 'tags: ' + (Pick $fm 'tags' '[]')
    $l1 += 'proposition_key: ' + (YamlStr (Pick $fm 'proposition_key' ($cat + '/' + $sub + '/' + $slug)))
    $l1 += '---'
    $l1 += ''
    $trimmed = $raw.TrimStart()
    if (-not $trimmed.StartsWith('# ')) { $l1 += '# ' + $title; $l1 += '' }
    $l1 += '## 原文（逐字保留）'
    $l1 += ''
    $l1 += $raw.TrimEnd()
    $l1 += ''
    $l1 += '## 来源信息'
    $l1 += ''
    $l1 += '- 提案：`_review/approved/' + $id + '.md`'
    $l1 += '- L0 副本：`' + $inboxRel + '`'
    $l1 += '- 用户原文件：`' + (Pick $fm 'origin_path' '') + '`'
    $l1 += '- 批准时间：' + $now
    Write-Text $dest (($l1 -join "`n") + "`n")
    Write-Ok ('[① L1 落盘] ' + $libRel)

    # ② 提案归档（保留审核痕迹）
    $archDir = Join-Path $script:KbRoot '_review\approved'
    Ensure-Dir $archDir | Out-Null
    $dst = Join-Path $archDir ($id + '.md')
    $k = 2
    while (Test-Path -LiteralPath $dst) { $dst = Join-Path $archDir ($id + '-archived' + $k + '.md'); $k++ }
    Move-Item -LiteralPath $src -Destination $dst
    $archName = [System.IO.Path]::GetFileName($dst)
    $archRel = '_review/approved/' + $archName
    $indexLine = '- [' + $id + '] ' + $title + ' — ' + (Get-OneLineSummary $raw) + ' [src:' + $id + ']'
    $arch = Read-Text $dst
    $arch = [regex]::Replace($arch, '(?m)^status:\s*.*$', 'status: approved')
    $bt = [char]96
    $arch = $arch.TrimEnd() + "`n`n## 审核记录`n`n"
    $arch += '- ' + $now + ' 用户批准（by=user），kb.cmd approve 执行文件层动作' + "`n"
    $arch += '- ① L1 落盘：' + $bt + $libRel + $bt + "`n"
    $arch += '- ② 提案归档：' + $bt + $archRel + $bt + "`n"
    $arch += '- ③ 日志：' + $bt + '_system/log.jsonl' + $bt + '（action=approve、by=user、l2_pending=true）' + "`n"
    $arch += '- ④ L2 engram_save：**待 agent 执行**（kb.ps1 永不写 engram）' + "`n"
    $arch += '- ⑤ L3 知识页更新：**待 agent 执行** → ' + $bt + 'pages/' + $cat + '.md' + $bt + "`n"
    $arch += "`n建议追加的索引行（agent 可直接用）：`n`n" + '```' + "`n" + $indexLine + "`n" + '```' + "`n"
    $arch += "`n完成 ④⑤ 后：把本文件 status 改为 indexed，并在 _system/log.jsonl 追加一行 " + $bt + '{"action":"l2-saved","id":"' + $id + '","by":"agent","l2_pending":false}' + $bt + "`n"
    Write-Text $dst $arch
    Write-Ok ('[② 提案归档] ' + $archRel)

    # ③ 可选：机械追加一行索引到知识页（默认不做，由 agent 决定综述内容）
    if ($UpdatePage) {
        Add-PageIndexLine $cat $indexLine
        Write-Ok ('[③ 知识页] pages\' + $cat + '.md 已机械追加 1 行索引（-UpdatePage）')
    }

    # ④ 日志（字段含 ts / action / id / by / l2_pending）
    Write-KbLog 'approve' $id ('l1=' + $libRel + ';archive=' + $archRel + ';l2_pending=true;l3_page_pending=pages/' + $cat + '.md') @{
        id          = $id
        by          = 'user'
        l2_pending  = $true
        l1          = $libRel
        l3_page     = 'pages/' + $cat + '.md'
    }

    # ⑤ 醒目下一步指令
    Write-Info ''
    Write-Warn2 '======================================================================'
    Write-Warn2 ' 【下一步：agent 必须接着做（kb.ps1 不写 engram、不默认改知识页）】'
    Write-Warn2 '======================================================================'
    Write-Info  (' A) 写 L2（契约 §4）+ 更新 L3，然后收尾：')
    Write-Info  ('    engram_save(')
    Write-Info  ('      kind    = "' + $kind + '",')
    Write-Info  ('      scope   = "' + $scope + '",')
    Write-Info  ('      content = "' + $linked + '"   # 必须含 [src:' + $id + ']')
    Write-Info  ('    )')
    Write-Info  (' B) 更新知识页 pages\' + $cat + '.md：')
    Write-Info  ('    「已入库条目索引」追加一行： ' + $indexLine)
    Write-Info  ('    「本类综述」更新 3-8 句（只放总览，不放原文），并把 entry_count / updated_at 改对。')
    Write-Info  (' C) 收尾（两步）：')
    Write-Info  ('    - 把 ' + $archRel + ' 的 status 改为 indexed；')
    Write-Info  ('    - 在 _system/log.jsonl 追加一行：{"action":"l2-saved","id":"' + $id + '","by":"agent","l2_pending":false}')
    Write-Info  (' D) 回到用户：提案 ' + $id + ' 已入库，L1=`' + $libRel + '`。')
    Write-Warn2 '======================================================================'
}

function Cmd-Reject([string]$id) {
    if ([string]::IsNullOrWhiteSpace($id)) { Fail 'reject 需要提案 id。例：kb.cmd reject kb-20261009-0001 -Reason "数字对不上"' }
    if ([string]::IsNullOrWhiteSpace($Reason)) { Fail 'reject 必须给出 -Reason 驳回理由（会被存档，便于以后回看）。' }
    $src = Join-Path (Join-Path $script:KbRoot '_review\queue') ($id + '.md')
    if (-not (Test-Path -LiteralPath $src)) { Fail ('待审队列里找不到提案 ' + $id + '。用 kb.cmd list-queue 查看。') }
    $fm = Get-Frontmatter (Read-Text $src)
    $now = (Get-Date).ToString('yyyy-MM-ddTHH:mm:sszzz')

    $rejDir = Join-Path $script:KbRoot '_review\rejected'
    Ensure-Dir $rejDir | Out-Null
    $dst = Join-Path $rejDir ($id + '.md')
    $k = 2
    while (Test-Path -LiteralPath $dst) { $dst = Join-Path $rejDir ($id + '-rejected' + $k + '.md'); $k++ }
    Move-Item -LiteralPath $src -Destination $dst
    $archName = [System.IO.Path]::GetFileName($dst)
    $archRel = '_review/rejected/' + $archName
    $doc2 = Read-Text $dst
    $doc2 = [regex]::Replace($doc2, '(?m)^status:\s*.*$', 'status: rejected')
    $doc2 = $doc2.TrimEnd() + "`n`n## 驳回记录`n`n- " + $now + ' 用户驳回（by=user）' + "`n- 理由：" + $Reason + "`n"
    Write-Text $dst $doc2
    Write-Ok ('[驳回] ' + $id + ' → ' + $archRel)

    # L1 材料移入 _inbox/_rejected/（用户原文件始终不动）
    $inboxRel = Pick $fm 'inbox_path' ''
    $moved = ''
    if ($inboxRel) {
        $inboxAbs = Join-Path $script:KbRoot ($inboxRel -replace '/', '\')
        if (Test-Path -LiteralPath $inboxAbs) {
            $rejInbox = Join-Path $script:KbRoot '_inbox\_rejected'
            Ensure-Dir $rejInbox | Out-Null
            $t = Join-Path $rejInbox ([System.IO.Path]::GetFileName($inboxAbs))
            $k2 = 2
            while (Test-Path -LiteralPath $t) { $t = Join-Path $rejInbox ([System.IO.Path]::GetFileNameWithoutExtension($inboxAbs) + '-' + $k2 + '.md'); $k2++ }
            Move-Item -LiteralPath $inboxAbs -Destination $t
            $moved = $t.Substring($script:KbRoot.Length + 1)
            Write-Info ('[材料] L0 副本已移入 ' + $moved + '（用户原文件未改动）')
        }
    }
    Write-Info '   该提案从未写入 L1（仅批准后才落盘 library/），未写 engram、未改知识页。'
    Write-KbLog 'reject' $id ('reason=' + $Reason + ';archive=' + $archRel + ';inbox=' + $moved) @{ id = $id; by = 'user'; l2_pending = $false }
}

function Cmd-Search([string]$query) {
    if ([string]::IsNullOrWhiteSpace($query)) { Fail 'search 需要关键词。例：kb.cmd search "vite 端口"' }
    $roots = @('library', 'pages', '_review\queue')
    $files = @()
    foreach ($r in $roots) {
        $abs = Join-Path $script:KbRoot $r
        if (Test-Path -LiteralPath $abs) { $files += @(Get-ChildItem -LiteralPath $abs -Recurse -File -Filter '*.md' -ErrorAction SilentlyContinue) }
    }
    if ($files.Count -eq 0) {
        Write-Info '库里还没有可检索的内容（library/ 与 pages/ 为空）。'
        Write-Info '流程：kb.cmd add -Path <资料文件> → agent 写提案 → 用户批准 → 才会进 library/。'
        return
    }
    $hits = @($files | Select-String -Pattern $query -SimpleMatch -ErrorAction SilentlyContinue)
    if ($hits.Count -eq 0) {
        Write-Info ('未在 L1 原文库 / L3 知识页 / 待审队列中命中「' + $query + '」。')
        Write-Info '建议：① 换关键词再搜；② 用 engram 混合检索（L2）；③ 联网补齐后走审核流程再入库。'
        Write-KbLog 'search' $query 'hits=0' @{ by = 'agent'; l2_pending = $false }
        return
    }
    Write-Ok ('命中 ' + $hits.Count + ' 处（L1 原文库 / L3 知识页 / 待审队列）：')
    Write-Info ''
    foreach ($g in ($hits | Group-Object Path)) {
        $rel = $g.Name.Substring($script:KbRoot.Length + 1)
        Write-Info ('📄 ' + $rel + '  (' + $g.Count + ' 处)')
        foreach ($m in ($g.Group | Select-Object -First 8)) {
            $line = $m.Line.Trim()
            if ($line.Length -gt 120) { $line = $line.Substring(0, 120) + '…' }
            Write-Info ('    L' + $m.LineNumber + ': ' + $line)
        }
        if ($g.Count -gt 8) { Write-Info ('    …还有 ' + ($g.Count - 8) + ' 处') }
    }
    Write-Info ''
    Write-Info '注意：这里是字面检索，结果是「原文位置」；回答问题时请用 L2 engram 检索 + 仲裁算法（_system/arbitration.md），并带 [src:<id>] 引用。'
    Write-KbLog 'search' $query ('hits=' + $hits.Count) @{ by = 'agent'; l2_pending = $false }
}

function Cmd-Page([string]$cat) {
    $cfg = $script:Cfg
    $pagesDir = Join-Path $script:KbRoot 'pages'
    if ([string]::IsNullOrWhiteSpace($cat)) {
        $files = @(Get-ChildItem -LiteralPath $pagesDir -File -Filter '*.md' -ErrorAction SilentlyContinue | Sort-Object Name)
        if ($files.Count -eq 0) { Write-Info '还没有知识页。先跑 kb.cmd init 生成 8 个大类的骨架。'; return }
        Write-Ok ('知识页共 ' + $files.Count + ' 张：')
        foreach ($f in $files) {
            $fm = Get-Frontmatter (Read-Text $f.FullName)
            Write-Info ('  ' + [System.IO.Path]::GetFileNameWithoutExtension($f.Name) + '   条目数=' + (Pick $fm 'entry_count' '0') + '   更新时间=' + (Pick $fm 'updated_at' '未更新'))
        }
        Write-Info ''
        Write-Info '查看：kb.cmd page <大类>'
        return
    }
    $p = Get-PagePath $cat
    if (-not (Test-Path -LiteralPath $p)) {
        if ($Create) {
            if ($cfg.categories -notcontains $cat) { Fail ('未知大类「' + $cat + '」。可选：' + ($cfg.categories -join '、')) }
            New-PageSkeleton $cat
            Write-Ok ('[OK] 已创建知识页 pages\' + $cat + '.md')
        } else {
            $avail = @()
            foreach ($f in (Get-ChildItem -LiteralPath $pagesDir -File -Filter '*.md' -ErrorAction SilentlyContinue)) { $avail += [System.IO.Path]::GetFileNameWithoutExtension($f.Name) }
            Fail ('没有 pages\' + $cat + '.md。现有：' + ($avail -join '、') + '；要新建加 -Create。')
        }
    }
    Write-Ok ('[知识页] pages\' + $cat + '.md')
    Write-Info ('-' * 100)
    Write-Info (Read-Text $p)
    Write-Info ('-' * 100)
    Write-KbLog 'page' $cat ('pages/' + $cat + '.md') @{ by = 'agent'; l2_pending = $false }
}

function Cmd-Log([int]$n) {
    $p = Join-Path $script:KbRoot '_system\log.jsonl'
    if (-not (Test-Path -LiteralPath $p)) { Write-Info '暂无操作日志（_system/log.jsonl 不存在，可先跑 kb.cmd init）。'; return }
    $lines = @(Get-Content -LiteralPath $p -Encoding UTF8 -ErrorAction SilentlyContinue | Where-Object { $_.Trim() -ne '' })
    if ($lines.Count -eq 0) { Write-Info '暂无操作日志。'; return }
    if ($n -le 0) { $n = 20 }
    $tail = @($lines | Select-Object -Last $n)
    Write-Ok ('最近 ' + $tail.Count + ' 条操作日志（共 ' + $lines.Count + ' 条）')
    Write-Info ''
    foreach ($l in $tail) {
        try {
            $o = ConvertFrom-Json $l
            Write-Info ('{0}  {1,-12} {2,-24} {3}' -f $o.ts, $o.action, $o.target, $o.note)
        } catch {
            Write-Info $l
        }
    }
}

# ============================================================
# 入口
# ============================================================

$script:Cfg = Get-Cfg

$cmd = $Command.Trim().ToLowerInvariant()
try {
    switch ($cmd) {
        'init' { Cmd-Init }
        'status' { Cmd-Status }
        'add' { Cmd-Add }
        'list-queue' { Cmd-ListQueue }
        'show' { Cmd-Show $Target }
        'approve' { Cmd-Approve $Target }
        'reject' { Cmd-Reject $Target }
        'search' { Cmd-Search $Target }
        'page' { Cmd-Page $Target }
        'log' { Cmd-Log $Tail }
        'help' { Show-Help }
        default {
            Write-Host ('[错误] 未知命令：' + $Command) -ForegroundColor Red
            Show-Help
            exit 1
        }
    }
} catch {
    Write-Host ('[错误] ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}
