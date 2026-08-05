/**
 * M0 acceptance — Globus, Smoke-Artefakt und Shots (A-M0-5, A-M0-9, A-M0-13,
 * A-M0-18, A-M0-19). Contract tests owned by the Reviewer (docs/12 §1).
 *
 * Artifact contract (CRITERIA.json O-M0-2 / O-M0-4 (e)):
 *   `pnpm run smoke` writes artifacts/smoke.json
 *       { consoleErrors: number, fps: number, frames: number }
 *   `pnpm run shots` uses tools/shots/config.json { seed, camera } and the
 *   committed first snapshots live under tools/shots/baseline/*.png.
 *
 * "60 fps" and "0 Console-Errors" are asserted against the EXECUTED smoke
 * run's artifact — claims without executed evidence do not count
 * (AGENTS.md §Integrität rule 4). Red before build is expected.
 */
import { execFileSync } from 'node:child_process'
import { existsSync, readdirSync } from 'node:fs'
import { describe, expect, it } from 'vitest'

import { anchorNumber, readJson, repoPath, repoRoot } from './helpers'

type SmokeReport = {
  consoleErrors: number
  fps: number
  frames: number
  renderer?: string
  gpuSyncMethod?: string
}
type ShotsConfig = { seed: number; camera: Record<string, unknown> }

const TARGET_FPS = anchorNumber('M0-target-fps')

/**
 * ADR-016 (E48): 60 fps (Anker M0-target-fps) bleibt Produktziel und gilt,
 * sobald Hardware-GL verfügbar ist. Liefert die Gate-Umgebung NACHWEISLICH
 * nur Software-GL (Renderer-String im Artefakt ist Pflicht), gilt dort
 * 30 fps als Regressions-Tripwire. Ein maskierter Renderer (z. B.
 * "WebKit WebGL") ist KEIN Nachweis — dann bleibt das 60-fps-Ziel scharf.
 * Messmethodik bleibt readPixels-1x1; Änderungen nur per ADR.
 */
// Anker statt Inline-Konstante seit der M2-Acceptance-Phase (BACKLOG E56).
const SOFTWARE_GL_TRIPWIRE_FPS = anchorNumber('M1-swgl-min-fps') // ADR-016 §E48.2
const SOFTWARE_GL_RENDERER = /swiftshader|llvmpipe|softpipe|swrast|software\s*(rasterizer|renderer|adapter)/i
const GPU_SYNC_METHOD = 'readPixels-1x1' // ADR-016 §E48.3

describe('A-M0-5: Three.js-Globus mit Displacement, Orbit-Kamera,', () => {
  it('three is a runtime dependency and src/render has a public API', () => {
    // The visual criterion itself (displaced globe, orbit camera) is judged
    // by the Reviewer on the deterministic shots (docs/12 §4 Gate 11);
    // here we pin the structural preconditions.
    const pkg = readJson<{ dependencies?: Record<string, string> }>(repoPath('package.json'))
    expect(pkg.dependencies?.three, 'three missing from dependencies').toBeTruthy()
    expect(existsSync(repoPath('src', 'render', 'index.ts'))).toBe(true)
  })
})

describe('A-M0-13: `pnpm run smoke` (Headless-Boot, 0 Console-Errors)', () => {
  it('smoke artifact exists (produced by an executed smoke run)', () => {
    expect(
      existsSync(repoPath('artifacts', 'smoke.json')),
      'artifacts/smoke.json missing — run `pnpm run smoke` first (contract O-M0-2)',
    ).toBe(true)
  })

  it('headless boot logged zero console errors', () => {
    const report = readJson<SmokeReport>(repoPath('artifacts', 'smoke.json'))
    expect(report.frames).toBeGreaterThan(0)
    expect(report.consoleErrors).toBe(0)
  })
})

describe('A-M0-9: 60 fps', () => {
  it('measured fps from the smoke run meets the anchored target for its declared GL environment (ADR-016)', () => {
    const report = readJson<SmokeReport>(repoPath('artifacts', 'smoke.json'))
    expect(Number.isFinite(report.fps)).toBe(true)
    expect(
      report.gpuSyncMethod,
      'gpuSyncMethod declaration missing or changed — Messmethodik ist per ADR-016 fixiert',
    ).toBe(GPU_SYNC_METHOD)
    const renderer = report.renderer ?? ''
    expect(
      renderer.length,
      'renderer declaration missing from smoke artifact (ADR-016: Pflichtfeld)',
    ).toBeGreaterThan(0)
    const provenSoftwareGl = SOFTWARE_GL_RENDERER.test(renderer)
    const target = provenSoftwareGl ? SOFTWARE_GL_TRIPWIRE_FPS : TARGET_FPS
    expect(
      report.fps,
      `fps ${report.fps.toFixed(2)} < ${target} — renderer "${renderer}" ${
        provenSoftwareGl
          ? '(nachgewiesenes Software-GL: Tripwire nach ADR-016 §E48.2)'
          : '(kein Software-GL-Nachweis: 60-fps-Produktziel gilt)'
      }`,
    ).toBeGreaterThanOrEqual(target)
  })
})

describe('A-M0-18 / A-M0-19: `pnpm run shots` (feste Kamera + Seed) inkl. Erst-Snapshots', () => {
  it('shots config pins a fixed camera and seed', () => {
    const config = readJson<ShotsConfig>(repoPath('tools', 'shots', 'config.json'))
    expect(typeof config.seed).toBe('number')
    expect(config.camera).toBeTruthy()
    expect(Object.keys(config.camera).length).toBeGreaterThan(0)
  })

  it('first snapshots are committed under tools/shots/baseline/', () => {
    const baselineDir = repoPath('tools', 'shots', 'baseline')
    expect(existsSync(baselineDir)).toBe(true)
    const pngs = readdirSync(baselineDir).filter((f) => f.endsWith('.png'))
    expect(pngs.length).toBeGreaterThan(0)
    for (const png of pngs) {
      const tracked = (() => {
        try {
          // ':(top)' anchors the pathspec at the repository toplevel so the
          // check also holds when the suite runs from a nested copy (e.g. the
          // Stryker sandbox under .stryker-tmp/) — same contract, see
          // REVIEW M1 E50/E55.
          execFileSync('git', ['ls-files', '--error-unmatch', `:(top)tools/shots/baseline/${png}`], {
            cwd: repoRoot,
            stdio: 'pipe',
          })
          return true
        } catch {
          return false
        }
      })()
      expect(tracked, `${png} not committed`).toBe(true)
    }
  })
})
