/**
 * Bundled `kb-curator` skill provider for the DeepSeek Harness.
 *
 * This package contributes one read-only skill. Its body and reference
 * documents ship inside `assets/kb-curator/`, and the knowledge-base engine
 * (`kb.ps1` / `kb.cmd` / `_system/` / `_templates/`) ships in
 * `assets/kb-curator/engine/`; the skill's resource base is the
 * `assets/kb-curator/` directory, so the base path the model receives already
 * resolves `engine/`, `references/` and `SKILL.md`.
 *
 * The skill is registered at {@link BUNDLED_SKILL_RANK}, the lowest precedence
 * rank. Any same-name skill from a filesystem root outranks it — project
 * `.dsh/skills` (100), project `.agents/skills` (200), custom roots (300),
 * `~/.dsh/skills` (400), `~/.agents/skills` (500) — so a user who already
 * curates `kb-curator` locally keeps their own copy and this provider's entry
 * is simply shadowed in the catalog rather than duplicated.
 *
 * @module dsh-kb-curator
 */

import { readFile } from 'node:fs/promises'
import { fileURLToPath } from 'node:url'
import { BUNDLED_SKILL_RANK } from '@deepseek-ai/dsh-skill'

/** Cordis plugin name. */
export const name = 'kb-curator'

/** Service required before the bundled provider can register. */
export const inject = ['skills']

/** Skill name contributed by this package; must equal the `SKILL.md` frontmatter `name`. */
export const SKILL_NAME = 'kb-curator'

/**
 * Catalog description surfaced to the model.
 *
 * This is the model's only trigger signal for the skill, so it must stay
 * byte-identical to the `description` field in `assets/kb-curator/SKILL.md`
 * frontmatter. `scripts/check-assets.mjs` fails the build when the two drift.
 */
export const SKILL_DESCRIPTION =
	'本地智能知识储备体系的策划与维护（三层：L1 原文库 / L2 engram 记忆 / L3 知识页）：喂资料、自动分类、生成待审提案、用户批准后才入库、五状态审核、来源引用、冲突仲裁与优先级裁定、召回答疑。当用户说「喂资料」「把这份资料存进知识库」「记到知识库」「归档一下」「有哪些待审」「审核」「批准入库」「通过这条」「驳回」「要改」「查库」「知识库里有没有」「资料冲突」「按优先级裁定」「knowledge base」「ingest」「curate」「approve」「arbitrate」「recall」「add to my KB」时使用本技能。'

/** Directory holding the skill body, its references and the bundled engine. */
const SKILL_DIR = new URL('../assets/kb-curator/', import.meta.url)

/** The skill body itself. */
const SKILL_BODY_URL = new URL('SKILL.md', SKILL_DIR)

/**
 * Resource base handed to the model with the skill body. `fileURLToPath`
 * already drops the trailing separator on Windows; the replace keeps POSIX
 * paths tidy and makes the reported base stable across platforms.
 */
const RESOURCE_BASE = Object.freeze({
	kind: 'directory',
	path: fileURLToPath(SKILL_DIR).replace(/[\\/]$/, ''),
})

const INVOCATION = Object.freeze({ modelInvocable: true, userInvocable: true })

/** Invocation-neutral catalog entry for the one skill this package owns. */
const CANDIDATE = Object.freeze({
	name: SKILL_NAME,
	description: SKILL_DESCRIPTION,
	invocation: INVOCATION,
	provider: SKILL_NAME,
	source: 'bundled',
	resourceBase: RESOURCE_BASE,
	rank: BUNDLED_SKILL_RANK,
	locator: SKILL_BODY_URL,
})

/**
 * Drop a leading YAML frontmatter block.
 *
 * The catalog entry already carries the parsed metadata, so the body the model
 * receives inside `<skill_instructions>` should be prose only. An absent or
 * unterminated delimiter means there is no frontmatter to strip and the text
 * is returned unchanged.
 *
 * @param text - raw `SKILL.md` contents.
 * @returns the body with any leading frontmatter block removed.
 */
function stripFrontmatter(text) {
	if (!text.startsWith('---')) return text
	const end = text.indexOf('\n---', 3)
	if (end === -1) return text
	const after = text.indexOf('\n', end + 1)
	return after === -1 ? '' : text.slice(after + 1).replace(/^\s*\n/, '')
}

/** The single provider this package registers. */
const provider = {
	name: SKILL_NAME,
	list: () => Promise.resolve([CANDIDATE]),
	async get() {
		return {
			name: CANDIDATE.name,
			description: CANDIDATE.description,
			invocation: CANDIDATE.invocation,
			provider: CANDIDATE.provider,
			source: CANDIDATE.source,
			resourceBase: CANDIDATE.resourceBase,
			content: stripFrontmatter(await readFile(SKILL_BODY_URL, 'utf8')),
		}
	},
}

/**
 * Register the bundled `kb-curator` provider on `ctx.skills`.
 *
 * @param ctx - Cordis context carrying the skill registry.
 */
export function apply(ctx) {
	ctx.skills.registerProvider(() => provider)
}
