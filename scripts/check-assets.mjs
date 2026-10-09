#!/usr/bin/env node
/**
 * Asset contract check for the `dsh-kb-curator` bundle.
 *
 * The bundle's value is entirely in its assets: the skill body, its reference
 * documents, and the knowledge-base engine. Nothing at install time validates
 * them, so this script does — with no dependencies beyond `node:` builtins, so
 * it runs in a fresh clone with no install step:
 *
 *   1. `SKILL.md` frontmatter parses, and its `name` / `description` are
 *      byte-identical to `lib/index.js`'s `SKILL_NAME` / `SKILL_DESCRIPTION`.
 *      Drift here is silent: the catalog would advertise one trigger while the
 *      body says something else.
 *   2. Every shipped asset exists and is non-empty.
 *   3. No shipped asset leaks a machine-specific path.
 *   4. Encoding rules hold: `kb.ps1` carries a UTF-8 BOM (Windows PowerShell
 *      5.1 otherwise reads it as ANSI and fails to parse the Chinese text),
 *      `kb.cmd` is pure ASCII (cmd.exe reads it in the OEM code page and would
 *      execute garbled bytes), and nothing else carries a BOM.
 *   5. The engine scaffold is coherent: `kb.config.json` parses, the log ships
 *      empty, and `cordis.patch.yml` names the installed package.
 *
 * Usage: `node scripts/check-assets.mjs` (also wired to `npm test`).
 *
 * @module dsh-kb-curator/scripts/check-assets
 */

import { readFile, readdir, stat } from 'node:fs/promises'
import { dirname, join, relative, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const SKILL_DIR = join(ROOT, 'assets', 'kb-curator')
const ENGINE_DIR = join(SKILL_DIR, 'engine')

/** Reference documents the skill body points at. */
const REFERENCES = [
	'arbitration.md',
	'architecture.md',
	'contract.md',
	'engram-usage.md',
	'kb-cli.md',
	'learning.md',
	'review-workflow.md',
]

/** Engine files the skill's commands need before `kb init` has ever run. */
const ENGINE_FILES = [
	'kb.ps1',
	'kb.cmd',
	'kb.config.json',
	'README.md',
	'_system/arbitration.md',
	'_system/entry-schema.md',
	'_system/learning.md',
	'_system/priority.yml',
	'_system/review-workflow.md',
	'_system/taxonomy.yml',
	'_templates/knowledge-page.md',
	'_templates/memory-entry.md',
	'_templates/review-proposal.md',
	'_templates/source-note.md',
]

/**
 * Substrings that must never reach a published asset.
 *
 * Each one is a path that only resolves on the author's machine; shipping it
 * would make the skill instruct an agent to read a directory that does not
 * exist for anyone else.
 */
const FORBIDDEN_SUBSTRINGS = [
	'E:\\KnowledgeBase',
	'E:/KnowledgeBase',
	'E:\\文档',
	'C:\\Users\\',
	'C:/Users/',
	'辉呀1加1',
	'default-workspace',
	'.dsh-beta',
	'kb-design',
]

/** Collected failures; the script exits non-zero if any survive. */
const failures = []

/**
 * Record one check result.
 *
 * @param ok - whether the check passed.
 * @param label - human-readable description of what was checked.
 * @param detail - optional explanation printed when the check failed.
 */
function check(ok, label, detail) {
	if (ok) {
		console.log(`  ok   ${label}`)
		return
	}
	failures.push(detail === undefined ? label : `${label} — ${detail}`)
	console.log(`  FAIL ${label}${detail === undefined ? '' : ` — ${detail}`}`)
}

/**
 * Read a file as UTF-8 and report whether it carried a BOM.
 *
 * @param path - absolute file path.
 * @returns decoded text plus the BOM flag.
 */
async function readText(path) {
	const raw = await readFile(path)
	const hasBom = raw.length >= 3 && raw[0] === 0xef && raw[1] === 0xbb && raw[2] === 0xbf
	return { text: raw.toString('utf8').replace(/^\uFEFF/, ''), hasBom, bytes: raw.length }
}

/**
 * Parse the two frontmatter fields a DSH skill must declare.
 *
 * The grammar is deliberately the narrow one the harness accepts: a leading
 * `---` line, `key: value` lines, and a closing `---`.
 *
 * @param text - full `SKILL.md` contents.
 * @returns parsed `name` and `description`, or null when no block is found.
 */
function parseFrontmatter(text) {
	if (!text.startsWith('---')) return null
	const end = text.indexOf('\n---', 3)
	if (end === -1) return null
	const fields = {}
	for (const line of text.slice(3, end).split('\n')) {
		const match = /^([A-Za-z0-9_-]+):\s?(.*)$/.exec(line)
		if (match !== null) fields[match[1]] = match[2].trim()
	}
	return fields
}

/**
 * Extract a single-quoted string constant from a source file.
 *
 * The check must not `import()` the plugin: it statically imports a peer
 * dependency that a bare clone does not have installed.
 *
 * @param source - JavaScript source text.
 * @param exportName - exported binding to read.
 * @returns the literal value, or null when it cannot be found.
 */
function readStringLiteral(source, exportName) {
	const match = new RegExp(`export const ${exportName} =\\s*'((?:[^'\\\\]|\\\\.)*)'`, 'u').exec(source)
	return match === null ? null : match[1].replace(/\\'/g, "'").replace(/\\\\/g, '\\')
}

console.log('dsh-kb-curator asset contract')

// ---- 1. SKILL.md frontmatter vs lib/index.js constants -----------------------
const skill = await readText(join(SKILL_DIR, 'SKILL.md')).catch(() => null)
check(skill !== null, 'assets/kb-curator/SKILL.md exists')
if (skill !== null) {
	const front = parseFrontmatter(skill.text)
	check(front !== null, 'SKILL.md carries a parseable frontmatter block')
	const libSource = await readText(join(ROOT, 'lib', 'index.js')).then((r) => r.text)
	const libName = readStringLiteral(libSource, 'SKILL_NAME')
	const libDescription = readStringLiteral(libSource, 'SKILL_DESCRIPTION')
	check(
		front?.name === libName,
		'SKILL.md frontmatter name matches lib/index.js SKILL_NAME',
		`frontmatter ${JSON.stringify(front?.name)} vs lib ${JSON.stringify(libName)}`,
	)
	check(
		front?.description === libDescription,
		'SKILL.md frontmatter description matches lib/index.js SKILL_DESCRIPTION',
		'the catalog trigger text and the skill body would disagree',
	)
	check(
		typeof libDescription === 'string' && libDescription.length > 0,
		'SKILL_DESCRIPTION is a non-empty string',
	)
	check(!/[\r\n]/.test(front?.description ?? ''), 'frontmatter description is a single line')
}

// ---- 2. every shipped asset exists and is non-empty -------------------------
for (const name of REFERENCES) {
	const info = await stat(join(SKILL_DIR, 'references', name)).catch(() => null)
	check(info !== null && info.size > 0, `references/${name} exists and is non-empty`)
}
for (const name of ENGINE_FILES) {
	const info = await stat(join(ENGINE_DIR, name)).catch(() => null)
	check(info !== null && info.size > 0, `engine/${name} exists and is non-empty`)
}

// ---- 3. no machine-specific path reaches a shipped asset -------------------
/** Every text file under `assets/kb-curator/`, relative to it. */
const shipped = []
for (const dir of [SKILL_DIR, join(SKILL_DIR, 'references'), ENGINE_DIR, join(ENGINE_DIR, '_system'), join(ENGINE_DIR, '_templates')]) {
	for (const entry of await readdir(dir, { withFileTypes: true })) {
		if (entry.isFile()) shipped.push(join(dir, entry.name))
	}
}
let leaks = 0
for (const path of shipped) {
	const { text } = await readText(path)
	for (const bad of FORBIDDEN_SUBSTRINGS) {
		if (text.includes(bad)) {
			leaks += 1
			failures.push(`${relative(ROOT, path)} contains machine-specific path ${JSON.stringify(bad)}`)
			console.log(`  FAIL ${relative(ROOT, path)} contains ${JSON.stringify(bad)}`)
		}
	}
}
check(leaks === 0, `no machine-specific paths in ${shipped.length} shipped asset files`)

// ---- 4. encoding rules -----------------------------------------------------
const ps1 = await readText(join(ENGINE_DIR, 'kb.ps1'))
check(ps1.hasBom, 'engine/kb.ps1 carries a UTF-8 BOM', 'Windows PowerShell 5.1 would read it as ANSI')
const cmd = await readFile(join(ENGINE_DIR, 'kb.cmd'))
check(
	cmd.every((byte) => byte < 0x80),
	'engine/kb.cmd is pure ASCII',
	'cmd.exe reads .cmd in the OEM code page and would execute garbled bytes',
)
for (const path of shipped) {
	if (path.endsWith('kb.ps1')) continue
	const { hasBom } = await readText(path)
	check(!hasBom, `${relative(ROOT, path)} carries no BOM`)
}

// ---- 5. engine scaffold coherence -----------------------------------------
const config = await readText(join(ENGINE_DIR, 'kb.config.json'))
try {
	const parsed = JSON.parse(config.text)
	check(Array.isArray(parsed.categories) && parsed.categories.length > 0, 'kb.config.json parses and lists categories')
	check(
		parsed.storage?.warn_free_gb > parsed.storage?.block_free_gb,
		'kb.config.json storage thresholds are ordered (warn above block)',
	)
} catch (error) {
	check(false, 'kb.config.json parses as JSON', String(error))
}
const log = await readFile(join(ENGINE_DIR, '_system', 'log.jsonl'))
check(log.length === 0, 'engine/_system/log.jsonl ships empty')

const pkg = JSON.parse(await readText(join(ROOT, 'package.json')).then((r) => r.text))
const patchPath = pkg.dsh?.bundle?.patch
check(typeof patchPath === 'string', 'package.json declares dsh.bundle.patch')
if (typeof patchPath === 'string') {
	const patch = await readText(join(ROOT, patchPath)).catch(() => null)
	check(patch !== null, `${patchPath} exists`)
	check(patch !== null && patch.text.includes(`name: '${pkg.name}'`), `${patchPath} mounts ${pkg.name}`)
}

// ---- verdict ---------------------------------------------------------------
console.log('')
if (failures.length > 0) {
	console.error(`FAILED: ${failures.length} check(s)`)
	for (const failure of failures) console.error(`  - ${failure}`)
	process.exit(1)
}
console.log('All asset checks passed.')
