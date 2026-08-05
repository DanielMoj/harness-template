/**
 * M0 acceptance — scaffolding, tooling and gate wiring.
 * Contract tests owned by the Reviewer (docs/12 §1). Criteria IDs map to
 * verbatim quotes in orchestrator/handoff/M0/CRITERIA.json (docs/07 §M0).
 * Red before implementation is expected — these tests ARE the contract.
 */
import { execFileSync } from 'node:child_process'
import { existsSync, readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'

import { readJson, repoPath, repoRoot } from './helpers'

type PackageJson = {
  scripts?: Record<string, string>
  dependencies?: Record<string, string>
  devDependencies?: Record<string, string>
}

const loadPackageJson = (): PackageJson => readJson<PackageJson>(repoPath('package.json'))

const allDeps = (pkg: PackageJson): Record<string, string> => ({
  ...pkg.dependencies,
  ...pkg.devDependencies,
})

const gitTracks = (path: string): boolean => {
  try {
    // ':(top)' anchors the pathspec at the repository toplevel so the check
    // also holds when the suite runs from a nested copy (e.g. the Stryker
    // sandbox under .stryker-tmp/) — same contract, see REVIEW M1 E50/E55.
    execFileSync('git', ['ls-files', '--error-unmatch', `:(top)${path}`], {
      cwd: repoRoot,
      stdio: 'pipe',
    })
    return true
  } catch {
    return false
  }
}

describe('A-M0-1: Vite+TS+pnpm, eslint/vitest, Verzeichnislayout aus AGENTS.md.', () => {
  it('package.json declares vite, vitest, eslint and typescript', () => {
    const deps = allDeps(loadPackageJson())
    for (const tool of ['vite', 'vitest', 'eslint', 'typescript']) {
      expect(deps[tool], `${tool} missing in package.json`).toBeTruthy()
    }
  })

  it('tsconfig is strict and does not skip lib checks (IMPLEMENTATION-RULES §Sprache & Typen)', () => {
    const tsconfig = readJson<{ compilerOptions?: Record<string, unknown> }>(
      repoPath('tsconfig.json'),
    )
    expect(tsconfig.compilerOptions?.strict).toBe(true)
    expect(tsconfig.compilerOptions?.skipLibCheck).toBe(false)
  })

  it('directory layout from AGENTS.md §Verzeichnislayout exists', () => {
    const layout = [
      'src/sim',
      'src/weapons',
      'src/data',
      'src/world',
      'src/render',
      'src/viz',
      'src/ui',
      'src/workers',
      'tools/pipeline',
      'tests',
    ]
    for (const dir of layout) {
      expect(existsSync(repoPath(dir)), `${dir} missing (AGENTS.md layout)`).toBe(true)
    }
  })
})

describe('A-M0-2: Pipeline-Minimum: `download.py` + `build_terrain.py` + `build_world.py`', () => {
  it.each(['download.py', 'build_terrain.py', 'build_world.py'])(
    'tools/pipeline/%s exists',
    (script) => {
      expect(existsSync(repoPath('tools', 'pipeline', script))).toBe(true)
    },
  )
})

describe('A-M0-7 / A-M0-8: ABOUT.md mit Lizenzvermerken.', () => {
  it('ABOUT.md exists and credits the M0 data sources (docs/03 §Lizenz-Pflichten)', () => {
    const aboutPath = repoPath('ABOUT.md')
    expect(existsSync(aboutPath)).toBe(true)
    const about = readFileSync(aboutPath, 'utf8')
    // M0 pipeline uses Copernicus GLO-30 (Quellenvermerk Pflicht) and
    // Natural Earth (PD — attribution still documented in ABOUT).
    expect(about).toMatch(/Copernicus/i)
    expect(about).toMatch(/Natural Earth/i)
  })
})

describe('A-M0-11..18: Gates eingerichtet (Scripts in package.json)', () => {
  // A-M0-11 test, A-M0-13 smoke, A-M0-14 mutgate, A-M0-15 graph:check,
  // A-M0-16 api:check, A-M0-17 assets:check, A-M0-18 shots.
  it.each(['test', 'smoke', 'mutgate', 'graph:check', 'api:check', 'assets:check', 'shots'])(
    'script "%s" is wired up',
    (script) => {
      const scripts = loadPackageJson().scripts ?? {}
      expect(scripts[script], `package.json script "${script}" missing`).toBeTruthy()
    },
  )

  it('A-M0-14: mutation testing (StrykerJS, docs/12 §4 Mutgate) is a dev dependency', () => {
    const deps = allDeps(loadPackageJson())
    const hasStryker = Object.keys(deps).some((name) => name.includes('stryker'))
    expect(hasStryker, 'StrykerJS missing from devDependencies').toBe(true)
  })

  it('A-M0-17: pipeline manifest for assets:check exists (docs/03: SHA256-Manifest)', () => {
    const manifest = readJson<Record<string, unknown>>(
      repoPath('tools', 'pipeline', 'manifest.json'),
    )
    expect(Object.keys(manifest).length).toBeGreaterThan(0)
  })
})

describe('A-M0-20: Lockfile committet', () => {
  it('pnpm-lock.yaml exists and is tracked by git', () => {
    expect(existsSync(repoPath('pnpm-lock.yaml'))).toBe(true)
    expect(gitTracks('pnpm-lock.yaml')).toBe(true)
  })
})

describe('A-M0-21: PROGRESS.md initialisiert.', () => {
  it('PROGRESS.md exists, is tracked and covers M0', () => {
    const progressPath = repoPath('PROGRESS.md')
    expect(existsSync(progressPath)).toBe(true)
    expect(gitTracks('PROGRESS.md')).toBe(true)
    expect(readFileSync(progressPath, 'utf8')).toMatch(/M0/)
  })
})
